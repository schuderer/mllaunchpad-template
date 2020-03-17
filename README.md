# mllaunchpad-template
Template for creating a Python Machine Learning Project that uses ML Launchpad.

When using this template, please replace the contents of this file with a description of your application.

The use case tackled here is https://github.com/schuderer/mllaunchpad/issues/60: deploying on a vanilla Linux machine from a different Windows/Linux machine.

While useful tools and technologies (think CI, setuptools, Docker, etc.) are out of scope for the issue above, template repositories for those use cases are very welcome!

The file build.py has been created to solve most points in abovementioned issue, using a central `deploy:` section in the model's config file. While a lot of useful tools exist and have been ignored (`nox`, different variants of `make` files, `setup.py`, `MANIFEST.ini`, `pip-tools`, etc.), the issue specifically states that the user should not have to maintain a lot of different configuration files. There are also a couple of scripts to help deploying on the server using gunicorn and nginx (see server_scripts), but this workflow is quite pedestrian/not-invented-here-like, and if you have access to any kind of deployment utilities, use those (even uWSGI Emperor would help).

## Steps to use:

The following assumes that your target system's Python version is 3.6, that you are on a Windows system, and that your project directory will be `c:\dev\code\myproject`.

Git-clone https://github.com/schuderer/mllaunchpad-template into `c:\dev\code\myproject` or, in case of SVN, download the zip file from https://github.com/schuderer/mllaunchpad-template and unzip into `c:\dev\code\myproject`.

The following are not really needed and can be deleted:
 - `server-scripts `
 - `requirements_frozen.txt`

Now that we have the project directory set up, let's get our Python development virtual environment ready:

If you use Anaconda as your (only) Python distribution, you need to first create a "clean" conda environment from which to create your dev virtual environment(s). Otherwise, skip this step. Open Anaconda Prompt, then type:

```console
> conda create -n python36 python=3.6
> conda activate python36
> conda install pip pyyaml packaging  # requirements of the build.py script
```

If you get an error about failed SSL verification, you might be behind a corporate firewall and may need to make your certificate known to conda (but please don't use `conda config --set ssl_verify false`!)

Create your development virtual environment.

```console
> cd c:\dev\code\myproject
> python -m venv .venv
```

Ignore in svn/add to .gitignore:
 - `.idea` recursively
 - `private` recursively
 - `.venv` recursively
 - `config_dev.yml` (this is your personal development copy)
 - `model_store` recursively
 - `build` recursively

At the beginning of each development session, and also now:

```console
> .venv\Scripts\activate
```

Check some things to be sure:

```console
> where python  # Should be in the path (...myproject/.venv/...)
```

```console
> python --version  # Should be (...3.6...)
```

Add/replace/adapt/develop:
 - python code in `app/` (leave `__init__.py` there, everything else in `app/` can be deleted/replaced)
 - edit the `config_dev.yml` (see documentation, you can adapt `config_deploy.yml` at a later point)
 - `requirements.txt` to contain your model's requirements
 - `requirements_dev.txt` to contain your development requirements (as well as a reference to the model's requirements `-r requirements.txt`)

For testing your code on your local machine, you need to install your development requirements:

```console
> pip install -r requirements_dev.txt
```

Please refer to the documentation at https://mllaunchpad.readthedocs.io on how to develop in and use ML Launchpad.

To build a deployment artifact, create a proper `config_deploy.yml` (which specifies the *unfrozen* `requirements.txt` for now), and run:

```console
> python build.py config_deploy.yml
```

**Tip:** If you are using a conda-based setup and you get an error like "Creating temporary environment ... ensurepip --upgrade ... returned non-zero exit status", you may need to deactivate your inner development venv (using `deactivate`), and make sure that only your plain conda environment from earlier is active (`conda activate python36`). The reason is that a mix of conda and venv does not play well with nested environments.

The script will ask you a bunch of questions. If in doubt, "y" is always the safest answer. You can use the "-y" parameter to automatically answer "y" to all questions: `python build.py -y config_deploy.yml`

One of the questions `build.py` will ask is whether to freeze (i.e. to pin) your unfrozen `requirements.txt`. Answer "y", and it will do it and automatically modify the config to use the frozen requirements from now on if you answer "y" to *that* question, too.

Once done, the directory `build` will contain the zipped deployment artifact. Move it to your server somehow. You may find the scripts in https://github.com/schuderer/mllaunchpad-template/tree/master/server_scripts useful.

