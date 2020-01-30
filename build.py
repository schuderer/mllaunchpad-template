from contextlib import contextmanager
from glob import glob
import os
import shutil
import platform
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
            "file": {},
            "platform": {},
            "save_to": {},
        },
        "python": {},
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


def delete_dir(path):
    if os.path.exists(path) and os.path.isdir(path):
        shutil.rmtree(path)


def create_dir(path):
    if not os.path.exists(path):
        os.makedirs(path)


def validate_config(config_dict, required, path=""):
    for item in required:
        path_start = (path + ":") if path else ""
        if item not in config_dict:
            raise ValueError("Missing key in config file: {}".format(path_start + item))
        validate_config(config_dict[item], required[item], path_start + item)


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


def load_req_file(req_file):
    # Check whether requirement versions are pinned
    with open(req_file) as f:
        req_str = f.read()
        if '==' not in req_str:
            print("\nWARNING: The requirements file specified in your config\n"
                  "does not seem to specify versions. It is highly recommended to only\n"
                  "deploy version-specific requirements (a.k.a. pinned requirements)\n"
                  "to ensure reproducibility even as pypi packages change.\n"
                  "Ideally, you would explicitly manage your requirements,\n"
                  "or create a frozen requirements file in a clean environment.\n"
                  "For the latter, see https://github.com/schuderer/mllaunchpad/issues/60\n")
            print("Do you REALLY want to continue with unpinned requirements?")
            yes = input("(Type 'yes' to continue anyway, Enter to quit (recommended)) ")
            if yes != "yes":
                sys.exit(0)
            else:
                print("Okay. Don't say I didn't warn ya.")
        return req_str


def run_pip(interpreter, req_cfg, params):
    url_params = []
    if "pip_index_url" in req_cfg and req_cfg["pip_index_url"]:
        url_params.extend(["--index-url", req_cfg["pip_index_url"]])
    if "pip_trusted_hosts" in req_cfg:
        for host in req_cfg["pip_trusted_hosts"]:
            url_params.extend(["--trusted-host", host])
    cmd = [interpreter, "-m", "pip", *params, *url_params]
    print(" ".join(cmd))
    return subprocess.Popen(cmd).wait()


def dependency_vulnerability_check(req_cfg):
    req_file = req_cfg["file"]
    print("Checking dependencies file {} for vulnerabilities...".format(req_file))
    with python_interpreter() as interpreter:
        inst_params = ["install", "--upgrade", "safety"]
        if run_pip(interpreter, req_cfg, inst_params) != 0:
            raise RuntimeError("An error occurred when installing the 'safety' vulnerability check package.")
        check_cmd = [interpreter, "-m", "safety", "check", "-r", req_file, "--full-report"]
        if "vulnerability_db" in req_cfg and req_cfg["vulnerability_db"]:
            check_cmd.extend(["--db", req_cfg["vulnerability_db"]])
        print(" ".join(check_cmd))
        if subprocess.Popen(check_cmd).wait() == 0:
            print("No vulnerabilities found.")
        else:
            raise AssertionError("Either vulnerabilities found in dependencies or error on executing check. See above for details.")


def get_requirements(req_cfg):
    req_file, target_platform, target_dir = req_cfg["file"], req_cfg["platform"], req_cfg["save_to"]
    print("Downloading requirements from {} for platform {}...".format(req_file, target_platform))
    with python_interpreter() as interpreter:
        delete_dir(target_dir)
        create_dir(target_dir)
        pip_params = ["download", "--platform", target_platform, "--no-deps", "-d", target_dir, "-r", req_file]
        if run_pip(interpreter, req_cfg, pip_params) != 0:
            raise RuntimeError("An error occurred when downloading the requirements.")


def get_model(config, config_file):
    store = config["model_store"]["location"]
    if os.path.relpath(store) in [os.path.relpath(os.path.dirname(p)) for p in config["deploy"]["include"] if os.path.dirname(p) != ""]:
        print("\nYour configuration's deploy:include setting specifies to deploy the model store.")
        model_name = "{}_{}".format(config["model"]["name"], config["model"]["version"])
        if os.path.exists(os.path.join(store, model_name + ".pkl")):
            print("If you don't re-train now, the existing model {} will be deployed.".format(model_name))
        else:
            print("There is no trained model to deploy, so model(s) will have to be trained in the target environment.")
        yn = input("Do you want to (re)train model {} now (y/n)? ".format(model_name))
        if yn.lower() == "y":
            with python_interpreter() as interpreter:
                req_cfg = config["deploy"]["requirements"]
                req_file = req_cfg["file"]

                print("Installing requirements from {}...".format(req_file))
                pip_params = ["install", "--upgrade", "-r", req_file]
                if run_pip(interpreter, req_cfg, pip_params) != 0:
                    raise RuntimeError("An error occurred when installing the requirements.")

                train_cmd = [interpreter, "-m", "mllaunchpad", "-c", config_file, "-t"]
                print(" ".join(train_cmd))
                train_result = subprocess.Popen(train_cmd).wait()
                if train_result != 0:
                    raise RuntimeError("An error occurred when training the model.")


def main():
    if len(sys.argv) != 2:
        raise ValueError("Expected config file as only command line argument.")
    config_file = sys.argv[1]

    with open(config_file) as f:
        config_str = f.read()
        config = yaml.safe_load(config_str)
        validate_config(config, required_config)

    major, minor = str(config["deploy"]["python"]).split(".")
    if str(sys.version_info[0]) != major or str(sys.version_info[1]) != minor:
        raise AssertionError("Your Python version {}.{} does not match the target Python version {}.{}".format(
            sys.version_info[0], sys.version_info[1], major, minor
        ))

    root_path = os.path.dirname(config_file)
    old_working_dir = os.getcwd()
    os.chdir(os.path.abspath(root_path))

    req_cfg = config["deploy"]["requirements"]
    req_str = load_req_file(req_cfg["file"])

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

    os.chdir(old_working_dir)
    print("\nDone. Build artifacts can be found in the '{}' subdirectory.".format(build_path))


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
