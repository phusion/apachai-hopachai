# About

Apachai Hopachai is a Continuous Integration (CI) system similar to [Travis CI](https://travis-ci.org/). Its main purpose is to run automated tests on every git push. Tests are run in an isolated environment so they can do anything, including running tests that require root privileges, without affecting the host machine.

## Highlights

Apachai Hopachai is built with a Unix-like architecture, meaning that it consists of multiple small components, each doing only one thing, but doing it well. The entire system is simply a collection of these small components integrated with each other. This makes the system transparent and easy to debug.

It is designed to run on one's own servers with minimal installation hassle. This allows it to be used with any privately hosted Git repository, not just those on Github.

It is also designed to be extremely lightweight. It uses [Docker](http://www.docker.io/) for isolation, instead of using virtual machines. This minimizes resource usage. You can run everything on just a single machine.

Apachai Hopachai uses the same configuration file format as Travis CI, `.travis.yml`. If you're already using Travis then using Apachai Hopachai should be easy. Note that Apachai Hopachai is still under development, so not all Travis config options are supported yet.

And because Docker requires a Linux 3.8 kernel, Apachai Hopachai only works on recent Linux distributions.

## System and usage overview

A typical Apachai Hopachai usage scenario looks like this:

 1. A developer runs `git push`.
 2. The Git server (often Github or Gitlab) posts a webhook request to Apachai Hopachai's webhook server, informing it that a git push has happened.
 3. The Apachai Hopachai webhook server runs `appa prepare` to prepare test jobs. These test jobs are saved to a queue directory.
 4. The Apachai Hopachai daemon (started through `appa daemon`) which was listening on the queue directory, notices new jobs, and runs them.
 5. Upon completion, the Apachai Hopachai daemon emails a report a configured email address.

## Installation through RubyGems

Install the following requirements:

 * [Docker](http://www.docker.io/gettingstarted/)
 * The `sendmail` command: `sudo apt-get install postfix`
 * The `inotifywatch` command: `sudo apt-get install inotify-tools`
 * Ruby 1.9:

        sudo apt-get install ruby1.9.1
        sudo update-alternatives --set ruby /usr/bin/ruby1.9.1
        sudo update-alternatives --set gem /usr/bin/gem1.9.1
 * Bundler: `sudo gem install bundler`
 * Runit (for managing the daemon): `sudo apt-get install runit`
 * [Phusion Passenger + Nginx](https://www.phusionpassenger.com/) (for serving the webhook server)

Then install the gem:

    sudo gem install apachai-hopachai
    sudo appa setup-symlinks && sudo appa build-image

### Setting up the daemon

Create a user for the daemon to run as:

    sudo adduser appa-daemon

Create a queue, log and PID directory:

    sudo mkdir -p /var/lib/appa-daemon/queue /var/log/appa-daemon /var/run/appa-daemon
    sudo chown -R appa-daemon:appa-daemon /var/lib/appa-daemon /var/log/appa-daemon /var/run/appa-daemon

Create a configuration file:

    sudo tee <<EOF >/etc/apachai-hopachai.yml
    queue_dir: /var/lib/appa-daemon/queue
    EOF
    sudo chown appa-daemon:appa-daemon /etc/apachai-hopachai.yml

Create a sudoers file:

    echo "appa-daemon ALL=(root)NOPASSWD:/usr/bin/docker" | sudo tee /etc/sudoers.d/appa-daemon
    sudo chmod 440 /etc/sudoers.d/appa-daemon

Create a Runit service for the Apachai Hopachai daemon:

    sudo mkdir -p /etc/service/appa-daemon
    sudo tee /etc/service/appa-daemon/run.new <<EOF >/dev/null
    #!/bin/bash
    EMAIL=me@myserver.com
    EMAIL_FROM=me@myserver.com
    export LANGUAGE=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    exec chpst -u appa-daemon nice ruby1.9.1 -S appa daemon \
      --log-file /var/log/appa-daemon/daemon.log \
      --pid-file /var/run/appa-daemon/daemon.pid \
      --docker-log-dir /var/log/appa-daemon \
      --sudo \
      --email \$EMAIL \
      --email-from \$EMAIL_FROM \
      /var/lib/appa-daemon/queue
    EOF
    sudo chmod +x /etc/service/appa-daemon/run.new
    sudo mv /etc/service/appa-daemon/run.new /etc/service/appa-daemon/run

Runit will automatically start the daemon. Be sure to customize the `EMAIL` and `EMAIL_FROM` fields. They specify what email address to send reports to, and what "From" address to use in such emails.

### Setting up the webhook

Install the gem bundle for the webhook server:

    cd /opt/appa-webapp
    sudo mkdir -p .bundle
    sudo chown -R appa-daemon:appa-daemon .bundle
    sudo -u appa-daemon bundle install --deployment --without=development --path=/var/lib/appa-daemon

Next, setup a virtual host entry for Phusion Passenger + Nginx to serve the webhook server:

    server {
        server_name yourdomain.com;  # Customize this!
        root /opt/appa-webapp/public;
        passenger_ruby /usr/bin/ruby1.9.1;
        passenger_enabled on;
        passenger_user appa-daemon;
    }

After restarting Nginx, your webhook is accessible through http://yourdomain.com/webhook. Fill in this address in Github or Gitlab.

## Upgrading

 1. Stop the daemon: `sudo sv stop /etc/service/appa-daemon`
 2. Install the latest version of Apachai Hopachai: `sudo gem install apachai-hopachai && sudo appa setup-symlinks && sudo appa build-image`
 3. Start the daemon: `sudo sv start /etc/service/appa-daemon`
 4. Reinstall the bundle for the webhook server, as described in "Setting up the webhook".
 5. Restart the webhook server: `sudo touch /opt/appa-webapp/tmp/restart.txt`, then restart Nginx.
