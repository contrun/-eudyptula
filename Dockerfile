FROM debian:unstable
RUN echo 'deb-src http://deb.debian.org/debian unstable main' >> /etc/apt/sources.list \
        && apt update \
        && apt-get -y build-dep linux \
        && apt-get -y install ccache fakeroot \
        && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/ccache:${PATH}"
WORKDIR	/build/kernel
ENTRYPOINT ["make"]
CMD ["deb-pkg"]
