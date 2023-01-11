ARG BASEIMAGE
ARG BASETAG

FROM ${BASEIMAGE}:${BASETAG} as stage_apt

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN \
    rm -rf /etc/apt/apt.conf.d/docker-clean \
	&& echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
	&& apt-get update


FROM ${BASEIMAGE}:${BASETAG} as stage_deps

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY deps/aptdeps.txt /tmp/aptdeps.txt

RUN \
    --mount=type=cache,target=/var/cache/apt,from=stage_apt,source=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt,from=stage_apt,source=/var/lib/apt \
    --mount=type=cache,target=/etc/apt/sources.list.d,from=stage_apt,source=/etc/apt/sources.list.d \
	apt-get install --no-install-recommends -y $(cat /tmp/aptdeps.txt) \
    && rm -rf /tmp/*

RUN \
    groupadd user \
    && useradd -ms /bin/bash user -g user


FROM stage_deps as stage_app

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY --chown=user:user deps/pydeps.txt /home/user/tmp/pydeps.txt
COPY --chown=user:user xformers/xformers-0.0.14.dev0-cp38-cp38-linux_x86_64.whl /home/user/tmp/xformers-0.0.14.dev0-cp38-cp38-linux_x86_64.whl
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /home/user

RUN \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git \
    && sed -i "s/COMMANDLINE_ARGS=\"\"/COMMANDLINE_ARGS=\"--xformers --listen --skip-torch-cuda-test\"/g" /home/user/stable-diffusion-webui/webui-user.sh \
    && curl -o /home/user/stable-diffusion-webui/javascript/auto_completion.js https://greasyfork.org/scripts/452929-webui-%ED%83%9C%EA%B7%B8-%EC%9E%90%EB%8F%99%EC%99%84%EC%84%B1/code/WebUI%20%ED%83%9C%EA%B7%B8%20%EC%9E%90%EB%8F%99%EC%99%84%EC%84%B1.user.js \
    && python3 -m venv /home/user/stable-diffusion-webui/venv \
    && source /home/user/stable-diffusion-webui/venv/bin/activate \
    && python3 -m pip install $(cat /home/user/tmp/pydeps.txt) \
    && python3 -m pip install /home/user/tmp/xformers-0.0.14.dev0-cp38-cp38-linux_x86_64.whl \
    && python3 -m pip install --upgrade --extra-index-url https://download.pytorch.org/whl/cu113 torch torchvision torchaudio \
    && chmod +x /home/user/stable-diffusion-webui/webui-user.sh \
    && rm -rf /home/user/tmp

COPY settings/run.sh /home/user/stable-diffusion-webui/run.sh
COPY settings/config.json /home/user/stable-diffusion-webui/config.json
COPY settings/styles.csv /home/user/stable-diffusion-webui/styles.csv
COPY settings/ui-config.json /home/user/ui-config.json.bak

RUN \
    chown -R user:user /home/user

LABEL title="Stable-Diffusion-Webui-Docker"
LABEL version="1.0.2"

EXPOSE 7860
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]

# DOCKER_BUILDKIT=1 docker build --no-cache \
# --build-arg BASEIMAGE=nvidia/cuda \
# --build-arg BASETAG=11.3-runtime-ubuntu20.04 \
# -t kestr3l/stable-diffusion-webui:1.0.2 \
# -f Dockerfile .

# docker run -it --rm \
#     -e NVIDIA_DISABLE_REQUIRE=1 \
#     -e NVIDIA_DRIVER_CAPABILITIES=all \
#     -e UID=$(id -u) \
#     -e GID=$(id -g) \
#     -v <DIR_TO_CHECKPOINT>:/home/user/stable-diffusion-webui/models/Stable-diffusion \
#     -v <DIR_FOR_OUTPUT>:/home/user/stable-diffusion-webui/outputs \
#     -v <DIR_TO_CONFIG>:/home/user/stable-diffusion-webui/config.json \
#     -v <DIR_TO_STYLES>:/home/user/stable-diffusion-webui/models/Stable-diffusion/styles.csv \
#     -v <DIR_TO_UI-CONFIG>:/home/user/ui-config.json.bak \
#     -p <PORT>:7860 \
#     --gpus all \
#     --privileged \
#     kestr3l/stable-diffusion-webui:1.0.2