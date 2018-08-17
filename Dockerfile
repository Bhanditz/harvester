FROM ruby:2.4.4
MAINTAINER Jeremy Rice <jrice@eol.org>
LABEL Description="EOL Harvester"

ENV LAST_FULL_REBUILD 2018-08-17

# Install packages
RUN apt-get update -q && \
    apt-get install -qq -y build-essential libpq-dev curl wget \
    apache2-utils nodejs procps supervisor vim nginx logrotate \
    libmagickwand-dev imagemagick && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app

# Install gnparser
RUN mkdir -p /u/tmp
RUN cd /u/tmp \
    && wget https://github.com/GlobalNamesArchitecture/gnparser/releases/download/release-0.4.2/gnparser-0.4.2.zip \
    && unzip gnparser-0.4.2.zip && mv gnparser-0.4.2 /u/apps/gnparser && rm -f /usr/local/bin/gnparser \
    && ln -s /u/apps/gnparser/bin/gnparser /usr/local/bin && rm -rf /u/tmp

COPY . /app
COPY config/nginx-sites.conf /etc/nginx/sites-enabled/default
# NOTE: supervisorctl and supervisord *service* doesn't work with custom config files, so just use default:
COPY config/supervisord.conf /etc/supervisord.conf
COPY Gemfile ./

RUN bundle install --jobs 10 --retry 5 --without test development staging

RUN touch /tmp/supervisor.sock
RUN chmod 777 /tmp/supervisor.sock

EXPOSE 3000