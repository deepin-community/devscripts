#! /bin/bash

# Purpose: install Debian packages in a Docker image
#
# Usage: deb2docker [options] packages
#   -B        do NOT build the image (default is to build)
#   -c CMD    command to run in the container (default to '/bin/bash')
#   -f FROM   indicate which distribution is to be used (default to debian:stable)
#   -h        show this help
#   -n NAME   name of the image (default to package list)
#   -o DIR    use given directory for the build (default in /tmp)
#   -p PRE    execute the given script during the container build (before packages install)
#   -s POST   execute the given script during the container build (after packages install)
#   -v        show package version
# The package list can be any Debian package, as well as local .deb
#
# Example: 'deb2docker -o /tmp/xeyes x11-apps' then '/tmp/xeyes/start xeyes'

# build:      docker build --rm Dockerfile
# run:        docker run   --rm -it NAME
# clean:      docker rmi NAME
# clean ALL:  docker system prune -a

# (c) E. Farhi - Synchrotron SOLEIL - GPL3

# requires: 
#   bash 
#   docker.io
# requires: docker privileges: 
#   sudo usermod -aG docker $USER

set -e

# default settings -------------------------------------------------------------
FROM=debian:stable
BUILD=1
NAME=
SETNAME=0
CMD="/bin/bash"
WORK_DIR=
SCRIPT=
PRE=
VERSION=1.0.8
ARGS="$@"

# handle input arguments -------------------------------------------------------
while getopts vhBf:n:c:o:d:p:s: flag
do
    case "${flag}" in
        h) # display help
        echo "Usage: $0 [-hB][-c CMD][-f FROM][-n NAME][-o DIR][-s SCRIPT] packages..."
        echo "  Build a Docker image with given Debian packages."
        echo "  Options:"
        echo "  -B        do NOT build the image (default is to build)"
        echo "  -c EXEC   command to run in the container (default to $CMD)"
        echo "  -f FROM   indicate which distribution is to be used (default to $FROM)"
        echo "  -h        show this help"
        echo "  -n NAME   name of the image (default to package list)"
        echo "  -o DIR    use given directory for the build (default is in /tmp)"
        echo "  -p PRE    execute script PRE before packages install"
        echo "  -s POST   execute script POST after packages install"
        echo "  -v        show package version"
        echo "  The package list can be any Debian package, as well as local .deb"
        echo " "
        echo "Example: '$0 -o /tmp/xeyes x11-apps' then '/tmp/xeyes/start xeyes'"
        exit 0; 
        ;;
        B) # do not build the image
        BUILD=0
        ;;
        f) # set FROM image
        FROM=${OPTARG}
        ;;
        n) # set image name
        NAME=${OPTARG}
        ;;
        c) # command to execute
        CMD=${OPTARG}
        ;;
        o|d) # output directory
        WORK_DIR=${OPTARG}
        ;;
        p) # PRE SCRIPT
        PRE=${OPTARG}
        ;;
        s) # SCRIPT (POST)
        SCRIPT=${OPTARG}
        ;;
        v) # VERSION
        echo "$0 version $VERSION"
        exit 0;
        ;;
        *)
        echo "ERROR: Invalid option. Use -h for help."
        exit 1;
        ;;
    esac
done
shift $((OPTIND-1))

# check that docker is installed
if ! command -v docker > /dev/null
then
    echo "ERROR: docker could not be found. Install it with: apt install docker.io"
    exit 1
fi

# set name when not set
if [ "x$NAME" = "x" ]; then
  SETNAME=1
fi

# create a temporary directory to work in --------------------------------------
if [ "x$WORK_DIR" = "x" ]; then
  N=`basename $0`
  WORK_DIR=`mktemp -p /tmp -d $N-XXXXXXXX`
else
  mkdir -p $WORK_DIR || echo "ERROR: Invalid directory $WORK_DIR"
fi
PW=$PWD


# search for executable commands -----------------
DEB=
# get a local copy of packages and find bin and desktop files
mkdir -p $WORK_DIR/apt      || exit # hold deb pkg copies for analysis

echo "$0: creating image $NAME in $WORK_DIR"
echo "Getting Debian packages..."
for i in $@; do
  echo "  $i"
  if [ -f "$i" ]; then
    cp $i $WORK_DIR/apt/
    n=`basename $i`
    DEB="$DEB /opt/install/$n"
  else
    DEB="$DEB $i"
    cd $WORK_DIR/apt
    apt download $i
    cd $PW
  fi
done


echo " "                                  >> $WORK_DIR/README
echo "Created with $0"                    >> $WORK_DIR/README
echo "$ARGS"                              >> $WORK_DIR/README
echo " "                                  >> $WORK_DIR/file_list.txt
for i in $WORK_DIR/apt/*.deb; do
  echo "Analyzing $i"
  
  N=$(dpkg-deb -f $i Package) || continue
  # set the container name if needed
  if [ "x$SETNAME" = "x2" ]; then
    NAME="$NAME-$N"
  fi
  if [ "x$SETNAME" = "x1" ]; then
    SETNAME=2
    NAME=$N
  fi
  echo "Package $N ------------------------------------------" >> $WORK_DIR/README
  dpkg-deb -I $i                                               >> $WORK_DIR/README
  
  F=`dpkg -c $i` 
  echo "$F" >> $WORK_DIR/file_list.txt
  echo " "  >> $WORK_DIR/README
  
done

# the base command to start the containers from image
cmd="docker run -it --net=host --env=DISPLAY --env='QT_X11_NO_MITSHM=1' --volume=\$HOME/.Xauthority:/home/user/.Xauthority:rw $NAME"

# prepare the Dockerfile -------------------------------------------------------
FILE="$WORK_DIR/Dockerfile"
DATE=`date`

if [ -f "$PRE" ]; then
  cp $PRE $WORK_DIR/
  N=`basename $PRE`
  PRE="RUN chmod a+x /opt/install/$N && sh -c \"/opt/install/$N\""
  PRE_FILE="ADD $N /opt/install/"
else
  PRE_FILE=
fi

if [ -f "$SCRIPT" ]; then
  cp $SCRIPT $WORK_DIR/
  N=`basename $SCRIPT`
  SCRIPT="RUN chmod a+x /opt/install/$N && sh -c \"/opt/install/$N\""
  SCRIPT_FILE="ADD $N /opt/install/"
else
  SCRIPT_FILE=
fi

echo "Creating Dockerfile $NAME into $FILE"
dd status=none of=${FILE} << EOF
# created by $0 on $DATE
# $ARGS
#
# Docker image $NAME
#
# build: docker build --rm Dockerfile
# run:   docker run --rm -it $NAME
# clean: docker rmi $NAME
# clean ALL: docker system prune -a

FROM $FROM

# copy required packages
ADD apt/  /opt/install/
ADD README /opt/install/
ADD file_list.txt /opt/install/
ADD Dockerfile /opt/install/
$PRE_FILE
$SCRIPT_FILE

# execute/install
$PRE
RUN apt-get update -y
RUN apt-get install -y --no-install-recommends bash xauth $DEB
$SCRIPT
RUN rm /opt/install/*.deb || echo " "

# start the container (interactive/terminal)
RUN useradd -ms /bin/bash user
ENV DISPLAY :0
USER user
CMD ["$CMD"]
EOF

# build docker -----------------------------------------------------------------
FILE=$WORK_DIR/build
dd status=none of=${FILE} << EOF
#!/bin/bash
# created by $0 on $DATE
# $ARGS
#
# build image $NAME
#
# Usage: build

docker build --rm -t $NAME .

# handle of Desktop launchers
mkdir -p launchers/
mkdir -p icons/

# get .desktop files ----------------------------------------------------------
D=\$(grep '\.desktop' file_list.txt) || echo "WARNING: No desktop files found."
# get the desktop files
D=\$(echo "\$D" | awk '{ print \$6 }')

# we need to copy them back, as well as their icons, and change the Exec lines
# create a container from image to access the files
id=\$(docker create $NAME)
for i in \$D; do
  docker cp \$id:\$i launchers/ || echo "WARNING: Failed to get desktop launcher \$i"
done

# get icon files --------------------------------------------------------------
D=\$(grep 'icon' file_list.txt) || echo "WARNING: No icon files found."
# get the icon files
D=\$(echo "\$D" | awk '{ print \$6 }')

# we need to copy them back, as well as their icons, and change the Exec lines
# create a container from image to access the files
id=\$(docker create $NAME)
for i in \$D; do
  docker cp \$id:\$i icons/ &> /dev/null|| echo "WARNING: Failed to get icon \$i"
done

# cleanup
docker rm -v \$id

# adapt the Desktop launchers to insert 'run', set Icons=
for i in launchers/*; do
  if [ ! -f "\$i" ]; then continue; fi
  I=\$(grep 'Icon=' \$i | cut -d = -f 2) || I=
  if [ ! -z "\$I" ]; then
    n=\`basename \$I\`
    if [ ! -f "icons/\$n" ]; then
      # get closest file that match Icon name when initial name is not present as a file
      n1=( icons/\$n* ) || n1=
      if [ ! -z "\$n1" ]; then
        n=\`basename \${n1[0]}\`
      fi
    fi
    sed -i "s|Icon=.*|Icon=icons/\$n|g" \$i   || echo " "
  fi
  I=\$(grep 'Exec=' \$i | cut -d = -f 2-) || I=
  sed -i "s|Exec=.*|Exec=sh -c \"echo '$NAME'; $cmd \$I\"|g" \$i                 || echo " "
  # make sure terminal is set (else 'docker -it' fails)
  I=\$(grep 'Terminal=' \$i | cut -d = -f 2) || I=
  if [ ! -z "\$I" ]; then
    sed -i 's|Terminal=.*|Terminal=true|g' \$i         || echo " "
  else
    echo "Terminal=true" >> \$i
  fi
  chmod a+x \$i                                         || echo " "
done

# create a Terminal launcher
echo "[Desktop Entry]"       > launchers/$NAME-terminal.desktop
echo "Type=Application"     >> launchers/$NAME-terminal.desktop
echo "Name=$NAME Terminal"  >> launchers/$NAME-terminal.desktop
echo "Terminal=true"        >> launchers/$NAME-terminal.desktop
echo "Exec=sh -c \"echo '$NAME'; $cmd\""            >> launchers/$NAME-terminal.desktop
chmod a+x                      launchers/$NAME-terminal.desktop
  
EOF
chmod a+x $WORK_DIR/build

if [ "x$BUILD" = "x1" ]; then
  # build the image
  (cd $WORK_DIR && ./build)

else
  echo "INFO: To build this image, use: cd $WORK_DIR; ./build"
  echo " "
  cat $WORK_DIR/build
fi

# ------------------------------------------------------------------------------
# get executables and Desktop launchers (from the Docker)
echo "------------------------------------------------------" >> $WORK_DIR/README
B=$(grep '\.desktop' $WORK_DIR/file_list.txt) || echo " "
echo "$B"                                                     >> $WORK_DIR/README

FILE=$WORK_DIR/start
dd status=none of=${FILE} << EOF
#!/bin/bash
# created by $0 on $DATE
#
# start a container from image $NAME
#
# Usage: start [CMD]
#   default CMD is $CMD

$cmd \$@
EOF
chmod a+x $WORK_DIR/start

# display final message
echo "--------------------------------------------"
echo "The image $NAME has been prepared in $WORK_DIR"
echo "  Desktop launchers are available in $WORK_DIR/launchers"
echo "To start $NAME, use:"
echo "  cd $WORK_DIR; ./start [cmd]"
echo " "
