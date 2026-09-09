FROM ghcr.io/evilmartians/lemans-fizzy@sha256:606372223ae2b1184a5973a8bbf4faa6fdfa16e039d3256b1234e9eeabf489a1

# SaaS mode on SQLite: the private queenbee client replaced by a local stand-in,
# a SQLite arm for the saas database, MySQL-only middleware guarded.
COPY saas-environment.patch /tmp/saas-environment.patch
RUN git apply --whitespace=nowarn /tmp/saas-environment.patch && rm /tmp/saas-environment.patch && \
    git add -A && git -c user.name=lemans -c user.email=lemans@localhost commit -q --amend -m "Initial commit"

ENV SAAS=1 \
    BUNDLE_GEMFILE=Gemfile.saas \
    STRIPE_WEBHOOK_SECRET=whsec_dev_only_secret

RUN bundle install && \
    rm -rf ~/.bundle/ /usr/local/bundle/ruby/*/cache /usr/local/bundle/ruby/*/bundler/gems/*/.git
