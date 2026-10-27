FROM ruby:3.4.12-slim-bookworm@sha256:549e18ddab0acedc09a63be26cc3bdb6c05988bf3ebccfd34fbc90869395097c AS base

WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates curl libjemalloc2 libjpeg62-turbo libpng16-16 libwebp7 libwebpdemux2 libwebpmux3 libltdl7 && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl --fail --silent --show-error https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc && \
    echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main' > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install --no-install-recommends -y postgresql-client-18 libpq5 && \
    rm -rf /var/lib/apt/lists/*

ENV LD_PRELOAD=libjemalloc.so.2

FROM base AS imagemagick
RUN apt-get update && apt-get install --no-install-recommends -y build-essential pkg-config xz-utils libjpeg62-turbo-dev libpng-dev libwebp-dev libltdl-dev && \
    curl --fail --location --silent --show-error https://github.com/ImageMagick/ImageMagick/releases/download/7.1.2-34/ImageMagick-7.1.2-34.tar.xz -o /tmp/imagemagick.tar.xz && \
    echo '55fe0ec246245b46c429f9e6bc65294ad4a78a66b88abd9817971ca157856323  /tmp/imagemagick.tar.xz' | sha256sum --check && \
    tar -xf /tmp/imagemagick.tar.xz -C /tmp && \
    cd /tmp/ImageMagick-7.1.2-34 && \
    ./configure --prefix=/opt/imagemagick --with-quantum-depth=8 --disable-hdri --disable-shared --disable-openmp --without-modules --without-perl --without-magick-plus-plus --without-x --with-png=yes --with-jpeg=yes --with-webp=yes && \
    make -j2 && make install

FROM base AS build
COPY --from=imagemagick /opt/imagemagick /opt/imagemagick
ENV PATH=/opt/imagemagick/bin:${PATH}
RUN apt-get update && apt-get install --no-install-recommends -y build-essential git libpq-dev && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 2.6.9 --no-document && bundle install --jobs 2 --retry 2
COPY . .
# Compile public assets without a database connection or runtime credentials.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec ruby bin/rails assets:precompile

FROM build AS verification
ENV BUNDLE_WITHOUT="" RAILS_ENV=test
RUN bundle install --jobs 2 --retry 2

FROM base
COPY --from=imagemagick /opt/imagemagick /opt/imagemagick
ENV PATH=/opt/imagemagick/bin:${PATH}
RUN groupadd --gid 1000 rails && useradd --uid 1000 --gid 1000 --create-home rails
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails
RUN mkdir -p tmp/pids log && chown -R rails:rails tmp log
USER rails
EXPOSE 3000
ENTRYPOINT ["bundle", "exec", "ruby", "bin/production-start"]
