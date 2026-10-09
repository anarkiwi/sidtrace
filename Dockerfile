# syntax=docker/dockerfile:1
#
# sidtrace: sidplayfp built from pinned upstream sources, patched so that
# setting the SIDTRACE environment variable streams a zstd-compressed CSV of
# every register-changing SID write.  Multi-stage so the (rarely changing)
# dependency builds are cached independently of the feature patch.

ARG DEBIAN=bookworm

# ---- pinned upstream revisions (bump these to track upstream) --------------
FROM debian:${DEBIAN}-slim AS build

ARG LIBRESIDFP_SHA=dcf6b8ac96a7aa385c75e9c9167914100fc61f78
ARG LIBSIDPLAYFP_SHA=72fee4871ae19987533f35e0f7719ae054d04282
ARG SIDPLAYFP_SHA=a3d5654bf750faf341efc56530dc4e2c1cbc8976
ARG MAKEFLAGS=-j4

ENV MAKEFLAGS=${MAKEFLAGS}

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool autoconf-archive pkg-config \
        git ca-certificates xa65 \
        libgcrypt20-dev libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# ---- 1. libresidfp (SID engine) — cached unless LIBRESIDFP_SHA changes ------
RUN git init -q /src/libresidfp && cd /src/libresidfp && \
    git remote add origin https://github.com/libsidplayfp/libresidfp.git && \
    git fetch -q --depth 1 origin "${LIBRESIDFP_SHA}" && git checkout -q FETCH_HEAD && \
    autoreconf -fi && ./configure --prefix=/usr/local && make && make install

# ---- 2. libsidplayfp (patched) ----------------------------------------------
# Full clone: the exsid/usbsid submodules carry m4 macros autoreconf requires.
RUN git clone -q https://github.com/libsidplayfp/libsidplayfp.git /src/libsidplayfp && \
    cd /src/libsidplayfp && git checkout -q "${LIBSIDPLAYFP_SHA}" && \
    git submodule update --init --recursive

# COPY the patches as late as possible so editing them does not bust the dep cache.
COPY patches/ /src/patches/
RUN cd /src/libsidplayfp && \
    git apply --verbose /src/patches/0001-sid-write-trace.patch && \
    git apply --verbose /src/patches/0002-deterministic-power-on-delay.patch && \
    autoreconf -fi && ./configure --prefix=/usr/local && make && make install

# ---- 3. sidplayfp frontend (unmodified) -------------------------------------
RUN git init -q /src/sidplayfp && cd /src/sidplayfp && \
    git remote add origin https://github.com/libsidplayfp/sidplayfp.git && \
    git fetch -q --depth 1 origin "${SIDPLAYFP_SHA}" && git checkout -q FETCH_HEAD && \
    autoreconf -fi && ./configure --prefix=/usr/local && make && make install && ldconfig

# ---- runtime ----------------------------------------------------------------
FROM debian:${DEBIAN}-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgcrypt20 libzstd1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/lib/libsidplayfp.so* /usr/local/lib/
COPY --from=build /usr/local/lib/libstilview.so* /usr/local/lib/
COPY --from=build /usr/local/lib/libresidfp.so* /usr/local/lib/
COPY --from=build /usr/local/bin/sidplayfp /usr/local/bin/sidplayfp
COPY bin/sidtrace /usr/local/bin/sidtrace
RUN ldconfig && chmod +x /usr/local/bin/sidtrace

# C64 ROMs are copyrighted and not bundled; mount your own read-only at
# /roms and pass --kernal/--basic/--chargen if a tune needs them.
WORKDIR /work
ENTRYPOINT ["sidtrace"]
