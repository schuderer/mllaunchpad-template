# mllaunchpad-template
Template for creating a Python Machine Learning Project that uses ML Launchpad.

When using this template, please replace the contents of this file with a description of your application.

The use case tackled here is https://github.com/schuderer/mllaunchpad/issues/60: deploying on a vanilla Linux machine from a different Windows/Linux machine.

While useful tools and technologies (think CI, setuptools, Docker, etc.) are out of scope for the issue above, template repositories for those use cases are very welcome!

The file build.py has been created to solve most points in abovementioned issue, using a central `deploy:` section in the model's config file. While a lot of useful tools exist and have been ignored (`nox`, different variants of `make` files, `setup.py`, `MANIFEST.ini`, `pip-tools`, etc.), the issue specifically states that the user should not have to maintain a lot of different configuration files. There are also a couple of scripts to help deploying on the server using gunicorn and nginx (see server_scripts), but this workflow is quite pedestrian/not-invented-here-like, and if you have access to any kind of deployment utilities, use those (even uWSGI Emperor would help).
