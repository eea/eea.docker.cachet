# Cachet Docker Image

This is based on the official [Docker image](https://hub.docker.com/r/cachethq/docker/) for [Cachet](https://github.com/CachetHQ/Cachet). 

[Cachet](https://github.com/CachetHQ/Cachet) is a beautiful and powerful open source status page system, a free replacement for services such as StatusPage.io, Status.io and others.

For full documentation, visit the [Installing Cachet with Docker](https://docs.cachethq.io/docs/get-started-with-docker) page.


# Quickstart

1. Clone this repository

  ```shell
  git clone https://github.com/eea/eea.docker.cachet
  ```

2. Edit the docker-compose.yml file to specify your [ENV variables](/conf/.env.docker).

__Note:__ You must specify a unique `APP_KEY` including `base64:` prefix generated by `php artisan key:generate` within the container.

3. Build and run the image

  ```shell
  docker-compose build
  docker-compose up
  ```

4. `eeacms/cachet`  runs on port 8000 by default. This is exposed on host port 8000 when using docker-compose.

# Docker Hub Automated build

`eeacms/cachet` is available as a [Docker Hub Trusted Build](https://hub.docker.com/r/eeacms/cachet/).

For a full list of Cachet versions released as Docker images  please see the [list of Docker hub tags](https://hub.docker.com/r/eeacms/cachet/tags/).


# Debugging

* The services such as Cachet, supervisord, nginx, and php-fpm log to `stdout` and `stderr`, and are visible in the Docker runtime output. 

* Setting the `DEBUG` Docker environment variable within the `docker-compose.yml` file or at runtime to `true` will enable debugging of the container entrypoint init script.
