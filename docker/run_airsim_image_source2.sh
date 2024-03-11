#!/bin/bash

# check if inside container
tput setaf 1
if [ -n "$DOCKER_MACHINE_NAME" ]; then
  >&2 echo "Error: You probably are already inside a docker container!"
  tput sgr 0
  exit 1
elif [ ! -e /var/run/docker.sock ]; then
  >&2 echo "Error: Either docker is not installed or you are already inside a docker container!"
  tput sgr 0
  exit 1
fi
tput sgr 0

# directories
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
AIRSIM_DIR="$(readlink -f "${SCRIPT_DIR}/../")"

# default config
GPU_NUM="all"
CONTAINER_NAME="AIRSIM-${GPU_NUM}"

IMAGE_REGISTRY=""
IMAGE_NAME="airsim_source"
IMAGE_TAG="5.2.0-opengl-ubuntu22.04" 
USER=1
IMAGE_REGISTRY=""
# read arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -m|--mount)
    MOUNT_DIRS+=("$2")
    shift # past argument
    shift # past value
    ;;
    -n|--name)
    CONTAINER_NAME="$2"
    shift # past argument
    shift # past value
    ;;
    --tag)
    IMAGE_TAG="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    SHOW_HELP=1
    break
    ;;
    *)    # invalid option
    if [[ $1 == -* ]]; then
      echo "Invalid argument '$1'."
      SHOW_HELP=1
      break
    else
      POSITIONAL+=("$1")
      shift # past argument
    fi
    ;;
  esac
done

# pass either all positional arguments or the shell to docker
if [ ${#POSITIONAL[@]} -eq 0 ]; then
  ARGS=${SHELL}
else
  ARGS="${POSITIONAL[@]}"
fi

# show help
if [ "$SHOW_HELP" = 1 ]; then
  echo "Usage: ./run_docker.bash [--deps] [--home] [--local] [-m|--mount DIR [-m|--mount DIR ...]] [--tag TAG] [-h|--help] [ENTRYPOINT]"
  echo ""
  echo "If no ENTRYPOINT is given, your shell ($SHELL) is used."
  echo ""
  echo "Options:"
  echo " * --user:         Use current user and group within the container and mount the home directory."
  echo " * --local:        Use local image instead of image from GitHub registry --> currently no uploaded github. it is private."
  echo " * -m|--mount DIR: Mount directory DIR"
  echo " * -n|--name NAME: Docker container name (default: AIRSIM)"
  echo " * --tag TAG:      Image tag (default: latest version)"
  echo " * -h|--help:      Show this message"
  echo ""
  exit 1
fi
HOSTNAME=$(whoami)

# docker arguments
DOCKER_ARGS=(
  -v "${AIRSIM_DIR}/ros2/":"/home/ue4/AirSim/ros2/":z
  -v "${AIRSIM_DIR}/Documents/":"/home/ue4/Documents/":z

  --runtime nvidia
  --network host
  # xserver access for visualization in test scripts
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  -e DISPLAY="${DISPLAY}"
  -v /usr/local/cuda:/usr/local/cuda

  # container name
  --name "${CONTAINER_NAME}"
  -h "${CONTAINER_NAME}"
  -e CONTAINER_NAME="${CONTAINER_NAME}"
  -e DOCKER_MACHINE_NAME="${CONTAINER_NAME}"
  -e PYTHONPATH="${PYTHONPATH}"
  # misc
  -it  # run container in interactive mode
  # --rm  # automatically remove container when it exits
  --ipc=host
  # --ulimit nofile=1024  # makes forking processes faster, see https://github.com/docker/for-linux/issues/502
)

# user
# DOCKER_ARGS+=(
# -v /etc/passwd:/etc/passwd:ro
# -v /etc/group:/etc/group:ro
# --user "$(id -u):$(id -g)"
# # -v "${HOME}:${HOME}"
# )

# my statement
# DOCKER_ARGS+=(-v /home/${HOSTNAME}/Dataset:/home/ue4/etri_bag:rw)
DOCKER_ARGS+=(--device /dev/input/js0)

# mount directories
for dir in "${MOUNT_DIRS[@]}"; do
  DOCKER_ARGS+=(-v "${dir}:${dir}")
done

# run container
if docker ps -a --format '{{.Names}}' | grep -w $CONTAINER_NAME &> /dev/null; then
	if docker ps -a --format '{{.Status}}' | egrep 'Exited' &> /dev/null; then
		echo "Container is already running. Attach to ${CONTAINER_NAME}"
		docker start $CONTAINER_NAME 	
		docker exec -w "/home/ue4" -it $CONTAINER_NAME bash --init-file /tmp/etri_env.sh
	elif docker ps -a --format '{{.Status}}' | egrep 'Created' &> /dev/null; then
		echo "Container is already created. Start and attach to ${CONTAINER_NAME}"
		docker start $CONTAINER_NAME 	
		docker exec -w "/home/ue4" -it $CONTAINER_NAME bash --init-file /tmp/etri_env.sh  
	elif docker ps -a --format '{{.Status}}' | egrep 'Up' &> /dev/null; then
		echo "Docker is already running"
		docker exec -w "/home/ue4" -it $CONTAINER_NAME bash --init-file /tmp/etri_env.sh
	fi 
else
  echo "Opening docker env...."
  docker run --privileged=true --gpus "device=${GPU_NUM}" \
    "${DOCKER_ARGS[@]}" \
    "${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}" \
    "${ARGS}" || exit 1
fi
