from contextlib import contextmanager
from glob import glob
import os
import shutil
from packaging.utils import canonicalize_name
import pkg_resources
import platform
import re
import subprocess
import sys
import venv

import yaml
from zipfile import ZipFile

required_config = {
    "model_store": {
        "location": {},
    },
    "model": {
        "name": {},
        "version": {},
    },
    "deploy": {
        "include": {},
        "requirements": {
            "python": {},
            "platforms": {},
            "file": {},
            "save_to": {},
            "vulnerability_db": {},
        },
    },
    "api": {
        "name": {},
        "version": {},
    },
}
venv_location = ".venv_temp_deploy"
build_path = "build"
deployed_config_name = "LAUNCHPAD_CFG.yml"
deployed_requirements_name = "LAUNCHPAD_REQ.txt"
required_python_name = "LAUNCHPAD_REQ_PYTHON.txt"
required_files_name = "LAUNCHPAD_REQ_FILES.txt"
base_url_file_name = "LAUNCHPAD_BASE_URL.txt"
constrain_download = False  # Experimental: specify python version and python implementation in 'pip download' command

# Unfortunately, some packages have BUILD requirements that they don't
# explicitly specify, but we need for installing on Linux.
# You only have to add something to this dict if training
# using the build script works, but you run into
# "Could not find version that satisfies..." errors when deploying!
# BUT (!!) it is smarter to first try to downgrade the offending packages
# until a wheel (.whl) file can be downloaded instead or source (tar.gz/zip).
patch_requirements = {
    "": ["setuptools", "gunicorn"]  # we will always need gunicorn to run our API
    # "packagename": ["requirements", "that this package needs", "but does't properly specify"],
    # "": ["setuptools"],  # always add if not present
    # "pandas": ["Cython"],
}
yes_to_all = False


def user_confirms(prompt):
    if yes_to_all:
        print(prompt + "y")
        return True
    yes = input(prompt)
    if yes and yes.lower().startswith("y"):
        return True
    else:
        return False


def delete_dir(path):
    if os.path.exists(path) and os.path.isdir(path):
        while os.path.exists(path):
            try:
                shutil.rmtree(path)
            except FileNotFoundError:
                pass


def create_dir(path):
    if not os.path.exists(path):
        os.makedirs(path)


def validate_config(config_dict, required, path=""):
    for item in required:
        path_start = (path + ":") if path else ""
        if item not in config_dict:
            raise ValueError("Missing key in config file: {}".format(path_start + item))
        validate_config(config_dict[item], required[item], path_start + item)
    if path == "" and "_" in config_dict["api"]["name"]:
        raise AssertionError("Config's api:name '{}' must not contain underscores".format(config_dict["api"]["name"]))


@contextmanager
def python_interpreter():
    print("Creating temporary environment {}...".format(venv_location))
    venv.create(venv_location, clear=True, with_pip=True)
    interpreter = os.path.join(
        venv_location,
        "Scripts" if platform.system() == "Windows" else "bin",
        "python")
    try:
        yield interpreter
    finally:
        print("Removing temporary environment {}".format(venv_location))
        delete_dir(venv_location)


class RequirementsNeedFreezing(Exception):
    pass


def load_req_file(req_file):
    # Check for implicit dependencies of requirements
    with open(req_file, "r+") as f:
        packages = [re.split("[=>< #]", l.strip())[0] for l in f.readlines()]
        required_sets = [patch_requirements[k] for k in patch_requirements.keys() if k == "" or k in packages]
        required_packages_duplicates = [p for s in required_sets for p in s]  # flatten list of lists
        required_packages = list(set(required_packages_duplicates))  # unique packages
        missing_packages = [p for p in required_packages if p not in packages]
        if missing_packages:
            print("\nYou need to add the packages {} to the requirements file.\n"
                  # "They are needed to install other packages on deployment.\n"
                  "After adding them, the requirements will have to be re-frozen.\n"
                  "Add them to requirements now?".format(missing_packages))
            if user_confirms("(Type 'y' to add, Enter to abort and do this yourself) "):
                lines_to_add = ["", "# Added by build script:"] + missing_packages
                f.write("\n".join(lines_to_add))
            else:
                sys.exit(0)
    # Check whether requirement versions are pinned
    with open(req_file) as f:
        req_str = f.read()
        trimmed_lines = [l.strip() for l in req_str.splitlines()]
        relevant_lines = [l for l in trimmed_lines if l and l[0] != "#" and l[0] != "-"]
        okay_lines = [True if "=" in l else False for l in relevant_lines]
        if not all(okay_lines):
            print(relevant_lines)
            print(okay_lines)
            print("\nWARNING: Not all entries in the requirements file specified in your config\n"
                  "seem to specify versions. It is highly recommended to only\n"
                  "deploy version-specific requirements (a.k.a. pinned requirements)\n"
                  "to ensure reproducibility even as pypi packages change.\n"
                  "Ideally, you would explicitly manage your dependencies' versions,\n"
                  "or create a frozen requirements file in a clean environment.\n"
                  "You can use this script to do the latter: 'build --freeze <config>'.\n"
                  "(for manual freezing, see https://github.com/schuderer/mllaunchpad/issues/60)\n")
            print("I can freeze the requirements for you now. Do you want me to do that?")
            if user_confirms("(Type 'y' to freeze, Enter to abort and solve the problem yourself) "):
                raise RequirementsNeedFreezing()
            else:
                sys.exit(0)
        return req_str


def run_pip(interpreter, req_cfg, params):
    url_params = []
    if "pip_index_url" in req_cfg and req_cfg["pip_index_url"]:
        url_params.extend(["--index-url", req_cfg["pip_index_url"]])
    if "pip_trusted_hosts" in req_cfg:
        for host in req_cfg["pip_trusted_hosts"]:
            url_params.extend(["--trusted-host", host])
    cmd = [interpreter, "-m", "pip", "--disable-pip-version-check", *params, *url_params]
    print(" ".join(cmd))
    output = subprocess.check_output(cmd).decode('ISO-8859-1')
    print(output)
    return output


def install_reqs(interpreter, config):
    req_cfg = config["deploy"]["requirements"]
    req_file = req_cfg["file"]

    print("Installing requirements from {}...".format(req_file))
    pip_params = ["install", "--upgrade", "-r", req_file]
    try:
        run_pip(interpreter, req_cfg, pip_params)
    except subprocess.CalledProcessError:
        raise RuntimeError("An error occurred when installing the requirements.")


def dependency_vulnerability_check(req_cfg):
    req_file = req_cfg["file"]
    print("Checking dependencies file {} for vulnerabilities...".format(req_file))
    with python_interpreter() as interpreter:
        inst_params = ["install", "--upgrade", "safety"]
        try:
            run_pip(interpreter, req_cfg, inst_params)
        except subprocess.CalledProcessError:
            raise RuntimeError("An error occurred when installing the 'safety' vulnerability check package.")
        check_cmd = [interpreter, "-m", "safety", "check", "-r", req_file, "--full-report"]
        if "vulnerability_db" in req_cfg and req_cfg["vulnerability_db"]:
            check_cmd.extend(["--db", req_cfg["vulnerability_db"]])
        print(" ".join(check_cmd))
        if subprocess.Popen(check_cmd).wait() == 0:
            print("No vulnerabilities found.")
        else:
            raise AssertionError("Either vulnerabilities found in dependencies or error on executing check. "
                                 "See above for details.")


def get_requirements(req_cfg):
    req_file, py_ver, target_platforms, target_dir = req_cfg["file"], req_cfg["python"], req_cfg["platforms"], req_cfg["save_to"]
    req_implementation = req_cfg.get("implementation", None)
    print("Downloading requirements from {} for platform tags {}...".format(req_file, target_platforms))
    with python_interpreter() as interpreter:
        delete_dir(target_dir)
        create_dir(target_dir)
        source_warnings = []
        with open(req_file) as rf:
            req_lines_raw = rf.read().splitlines()
            req_lines = [l.split(" ")[0] for l in req_lines_raw]
        for req_line in req_lines:
            source_files = []
            for target_platform in target_platforms:
                pip_params = ["download"]
                if constrain_download:
                    pip_params.extend(["--python-version", py_ver])
                    if req_implementation:
                        pip_params.extend(["--implementation", req_implementation])
                pip_params.extend(["--platform", target_platform, "--no-deps", "-d", target_dir, req_line])
                # pip_params = ["download", "--platform", target_platform, "--no-deps", "-d", target_dir, "-r", req_file]
                # pip_params = ["download", "--platform", target_platform, "--no-deps", "--prefer-binary", "-d", target_dir, "-r", req_file]
                try:
                    output = run_pip(interpreter, req_cfg, pip_params)
                    file_matches = re.findall(r" (?:File was already downloaded|Saved) ([^\n\r]+)[\n\r]", output)
                    if len(file_matches) != 1:
                        raise RuntimeError("Unable to find out whether the package {} could be downloaded.".format(req_line))
                    file = file_matches[0]
                    if file.endswith(".tar.gz") or file.endswith(".zip"):
                        print("Platform {} yielded source file {}\n".format(target_platform, file))
                        source_files.append(file)
                        source_warnings.append(req_line)
                    else:
                        print("Found a wheel for {} using platform tag {}\n".format(req_line, target_platform))
                        source_warnings = [r for r in source_warnings if r != req_line]
                        for f in source_files:
                            try:
                                os.remove(f)
                            except FileNotFoundError:
                                pass
                        break
                except subprocess.CalledProcessError:
                    raise RuntimeError("An error occurred when downloading the requirements.")
        source_warnings = list(set(source_warnings))  # unique
        if source_warnings:
            print("\nWARNING: No matching wheels could be found for the dependencies {}".format(source_warnings))
            print("so source code packages (tar.gz/zip) have been downloaded instead of wheels.")
            print("In many cases, such as for pure python packages such as 'dill', this is not a problem.")
            print("But particularly C-backed packages like 'pandas' would then be tried to be compiled")
            print("on the target system, probably lacking some build dependencies, and complain about that.")
            print("While it is possible to install the build dependencies, it is preferable to look at")
            print("pypi.org whether a previous version of the offending package comes with a wheel for")
            print("your target platform and then adjust the (frozen) dependencies to this version.")
            if not user_confirms("\nType 'y' to continue anyway (usually worth a try), Enter to abort. "):
                sys.exit(0)


def get_model(config, config_file):
    store = config["model_store"]["location"]
    if os.path.relpath(store) in [os.path.relpath(os.path.dirname(p)) for p in config["deploy"]["include"] if os.path.dirname(p) != ""]:
        print("\nYour configuration's deploy:include setting specifies to deploy the model store.")
        model_name = "{}_{}".format(config["model"]["name"], config["model"]["version"])
        if os.path.exists(os.path.join(store, model_name + ".pkl")):
            print("If you don't re-train now, the existing model {} will be deployed.".format(model_name))
        else:
            print("There is no trained model to deploy, so you either have to train the model now,\n"
                  "or model(s) will have to be trained in the target environment.")
        if user_confirms("Type 'y' to (re)train model {} now, Enter to continue without training: ".format(model_name)):
            with python_interpreter() as interpreter:
                install_reqs(interpreter, config)
                train_cmd = [interpreter, "-m", "mllaunchpad", "-c", config_file, "-t"]
                print(" ".join(train_cmd))
                train_result = subprocess.Popen(train_cmd).wait()
                if train_result != 0:
                    raise RuntimeError("An error occurred when training the model.")


def get_config(config_file):
    with open(config_file) as f:
        config_str = f.read()
        config = yaml.safe_load(config_str)
        validate_config(config, required_config)
    return config, config_str


def get_inv_requirements_graph():
    inv_req_graph = {}
    for pkg in pkg_resources.working_set:
        for required in pkg.requires():
            req_name = canonicalize_name(required.name)
            req_version_spec = str(required.specifier)
            pkg_name = canonicalize_name(pkg.project_name)
            pkg_version = pkg.version

            if req_name not in inv_req_graph:
                inv_req_graph[req_name] = [(pkg_name, pkg_version, req_version_spec)]
            else:
                inv_req_graph[req_name].append((pkg_name, pkg_version, req_version_spec))
    return inv_req_graph


def add_req_description(inv_req_graph, req_file_line):
    indent = 30
    line = req_file_line.strip()
    req = re.split("[><= #]", line)[0]
    req_canonical = canonicalize_name(req)
    via_version_list = inv_req_graph[req_canonical] if req_canonical in inv_req_graph else []
    comment = ""
    for via_pkg, via_pkg_version, version in via_version_list:
        if not via_pkg.startswith("-r "):
            if comment:
                comment += " and by "
            comment += "{} {}".format(via_pkg, via_pkg_version)
            if version:
                comment += " ({}{})".format(req_canonical, version)
    spaces = max(indent - len(line), 2)
    if comment:
        to_add = (spaces * " ") + "# required by " + comment
        line_new = line + to_add
    else:
        line_new = line
    return line_new


def freeze_reqs(config_file):
    """Returns True if config has been changed and can be reloaded, False if user has to handle this themselves."""
    config, config_str = get_config(config_file)

    with python_interpreter() as interpreter:
        install_reqs(interpreter, config)
        old_reqs_file = config["deploy"]["requirements"]["file"]
        if "_frozen." in old_reqs_file:
            frozen_reqs_file = old_reqs_file
        else:
            frozen_reqs_file_name, ext = os.path.splitext(old_reqs_file)
            frozen_reqs_file = "{}_frozen{}".format(frozen_reqs_file_name, ext)

        freeze_cmd = [interpreter, "-m", "pip", "freeze", "--all"]  # --all is needed for setuptools, wheel
        try:
            print(" ".join(freeze_cmd) + " > " + frozen_reqs_file)
            freeze_output = subprocess.check_output(freeze_cmd).decode('ISO-8859-1')
        except subprocess.CalledProcessError:
            raise RuntimeError("An error occurred when freezing the requirements.")
        with open(frozen_reqs_file, "w") as out:
            inv_req_graph = get_inv_requirements_graph()
            for req_file_line in freeze_output.splitlines():
                line_new = add_req_description(inv_req_graph, req_file_line)
                out.write(line_new + "\n")

        print("Froze the requirements {} into {}".format(old_reqs_file, frozen_reqs_file))

        if frozen_reqs_file != old_reqs_file:
            print("\nI can modify the config {} for you to include {} instead of {}".format(
                config_file, frozen_reqs_file, old_reqs_file))
            if user_confirms("(Type 'y' to update the config file now, press Enter to handle this manually later) "):
                config_file_old = "{}_before_freeze{}".format(*os.path.splitext(config_file))
                shutil.move(config_file, config_file_old)
                regex = re.compile(r"\s+file:\s*[\"']?({})[\"']?\s*#?[^\n\r]*".format(old_reqs_file), re.MULTILINE)
                matches = regex.findall(config_str)
                if len(matches) != 1:
                    raise ValueError("Could not update config file. Expected exactly one location where to change "
                                     "{} to {}, but found {} locations".format(old_reqs_file, frozen_reqs_file, len(matches)))
                with open(config_file, "w") as new_file:
                    for line in config_str.splitlines():
                        if regex.match(line):
                            line = line.replace(old_reqs_file, frozen_reqs_file)
                        # print(line)
                        new_file.write(line + "\n")

                print("\nFroze the requirements {} into {} \n"
                      "and modified the config file {} to include them. \n"
                      "The previous config file has been backed up to {}".format(
                        old_reqs_file,
                        frozen_reqs_file,
                        config_file,
                        config_file_old))

        return True
    return False


def main():
    # TODO: use Click
    args = sys.argv[1:]
    global yes_to_all
    if "-y" in args or "--yes-to-all" in args:
        yes_to_all = True
        args = [a for a in args if a != "-y" and a != "--yes-to-all"]

    if "-f" in args or "--freeze" in args:
        if len(args) != 2:
            raise ValueError("Freezing requirements requires a config file with a reference to the unfrozen file in \n"
                             "deploy:requirements:file. "
                             "It will create a <filename>_frozen.txt and change \n"
                             "your deployment config's deploy:requirements:file to <filename>_frozen.txt.")
        config_file = [a for a in args if a != "-f" and a != "--freeze"][0]
        freeze_reqs(config_file)
        sys.exit(0)

    if len(args) != 1:
        raise ValueError("Expected single argument with config file.")
    config_file = args[0]

    config, config_str = get_config(config_file)

    major, minor = str(config["deploy"]["requirements"]["python"]).split(".")
    if str(sys.version_info[0]) != major or str(sys.version_info[1]) != minor:
        raise AssertionError("Your Python version {}.{} does not match the target Python version {}.{}".format(
            sys.version_info[0], sys.version_info[1], major, minor
        ))

    root_path = os.path.dirname(config_file)
    old_working_dir = os.getcwd()
    os.chdir(os.path.abspath(root_path))

    req_cfg = config["deploy"]["requirements"]
    try:
        req_str = load_req_file(req_cfg["file"])
    except RequirementsNeedFreezing:
        reload = freeze_reqs(config_file)
        if reload:
            # Continue script
            config, config_str = get_config(config_file)
            req_cfg = config["deploy"]["requirements"]
            req_str = load_req_file(req_cfg["file"])
        else:
            print("\nPlease update your config file's deploy:requirements:file to point \n"
                  "to the frozen requirements and run 'python build.py <config_file> again.")
            sys.exit(0)

    get_model(config, config_file)

    dependency_vulnerability_check(req_cfg)

    get_requirements(req_cfg)

    files = []
    for file_pattern in config["deploy"]["include"]:
        expanded_files = glob(file_pattern, recursive=True)
        filtered_files = []
        for f in expanded_files:
            if "exclude" in config["deploy"]:
                unwanted = [e for e in config["deploy"]["exclude"] if e in f]
            else:
                unwanted = []
            if len(unwanted) == 0:
                filtered_files.append(f)
        files.extend(filtered_files)

    delete_dir(build_path)
    create_dir(build_path)
    zip_name = os.path.join(build_path, "{}_{}.zip".format(config["api"]["name"], config["api"]["version"]))
    print("Packaging zip file {}...".format(zip_name))
    with ZipFile(zip_name, 'w') as zip_file:
        for file in files:
            print("Adding file {}".format(file))
            zip_file.write(file)
        print("Adding file {}".format(deployed_config_name))
        zip_file.writestr(deployed_config_name, config_str)
        print("Adding file {}".format(deployed_requirements_name))
        zip_file.writestr(deployed_requirements_name, req_str)
        print("Adding file {}".format(required_python_name))
        zip_file.writestr(required_python_name, "{}{}".format(major, minor))
        print("Adding file {}".format(required_files_name))
        required_files_str = ""
        if "deployment_requires" in config["deploy"]:
            required_files_str = "\n".join(config["deploy"]["deployment_requires"]).replace("\\", "/")
        zip_file.writestr(required_files_name, required_files_str)
        print("Adding file {}".format(base_url_file_name))
        base_url = "{}/v{}/".format(config["api"]["name"],
                                    config["api"]["version"].split(".")[0])
        zip_file.writestr(base_url_file_name, base_url)

    os.chdir(old_working_dir)
    print("\nDone. Build artifacts can be found in the '{}' subdirectory.".format(build_path))


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
