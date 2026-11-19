FROM mcr.microsoft.com/devcontainers/base:debian

ARG JULIA_VER=1.12.1
ARG JULIA_MINOR=1.12
ENV MAMBA_ROOT_PREFIX=/opt/mamba
ENV BSAT_ENV=/opt/envs/bsat
ENV BSAT_DASHBOARD_ENV=/opt/envs/bsat-dashboard
ENV JULIA_DEPOT_PATH=/opt/julia-depot

# micromamba (single static binary)
RUN curl -L "https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-linux-64" \
      -o /usr/local/bin/micromamba && chmod +x /usr/local/bin/micromamba

# conda envs: R for the pipeline, Python for the local dashboard (precompiled, conda-forge)
COPY setup/environment.yml /tmp/environment.yml
COPY setup/environment-dashboard.yml /tmp/environment-dashboard.yml
RUN micromamba create -y -p ${BSAT_ENV} -f /tmp/environment.yml && \
    micromamba create -y -p ${BSAT_DASHBOARD_ENV} -f /tmp/environment-dashboard.yml && \
    micromamba clean -a -y

# official portable Julia
RUN curl -L "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MINOR}/julia-${JULIA_VER}-linux-x86_64.tar.gz" \
      -o /tmp/julia.tar.gz && \
    mkdir -p /opt/julia && tar -xzf /tmp/julia.tar.gz -C /opt/julia --strip-components=1 && \
    rm /tmp/julia.tar.gz

# shared, writable Julia depot so postCreate (non-root user) can instantiate
RUN mkdir -p ${JULIA_DEPOT_PATH} && chown -R 1000:1000 ${JULIA_DEPOT_PATH}

ENV PATH=${BSAT_ENV}/bin:${BSAT_DASHBOARD_ENV}/bin:/opt/julia/bin:${PATH}
