#! /bin/bash

# Purpose: install Debian packages in a Singularity/Apptainer image
#
# Usage: deb2apptainer [options] packages
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
# Example: 'deb2apptainer -o /tmp/xeyes x11-apps' then '/tmp/xeyes/start xeyes'

# (c) E. Farhi - Synchrotron SOLEIL - GPL3

# requires:
#   bash 
#   apptainer.deb from https://apptainer.org/docs/admin/main/installation.html#install-debian-packages

# info:   apptainer inspect    image.sif
# header: apptainer sif header image.sif
# data:   apptainer sif list   image.sif

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

# handle input arguments -------------------------------------------------------
while getopts vhBf:n:c:o:d:p:s: flag
do
    case "${flag}" in
        h) # display help
        echo "Usage: $0 [-hB][-c CMD][-f FROM][-n NAME][-o DIR][-s SCRIPT] packages..."
        echo "  Build a Singularity/Apptainer image with given Debian packages."
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

# check that apptainer is installed
if ! command -v apptainer > /dev/null
then
    echo "ERROR: apptainer could not be found. Install it from"
    echo "       https://apptainer.org/docs/admin/main/installation.html#install-debian-packages"
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


# search for executable commands and launchers in the packages -----------------
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
    DEB="$DEB /opt/install/apt/$n"
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
  
  N=$(dpkg-deb -f $i Package)  || continue
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

# prepare the Singularity definition file --------------------------------------
FILE="$WORK_DIR/$NAME.def"
DATE=`date`

# get a random UUID for /etc/machine-id
# see:
# - https://github.com/denisbrodbeck/machineid/issues/5
# - https://github.com/apptainer/singularity/issues/3609
if command -v uuidgen > /dev/null
then
  UUID=`uuidgen | sed "s/-//g"`
  UUID="echo $UUID > /etc/machine-id"
else
  if [ -f "/etc/machine-id" ]; then
    UUID=`cat /etc/machine-id`
    UUID="echo $UUID > /etc/machine-id"
  else
    UUID=0de1bbc1982243198b320e756d12224b
  fi
fi

# the base command to start the containers from image
cmd="apptainer run $NAME.sif "
if [ "x$CMD" = "x/bin/sh" -o "x$CMD" = "x/bin/bash" ]; then
  cmd_arg="-c"
else
  cmd_arg=""
fi

if [ -f "$PRE" ]; then
  cp $PRE $WORK_DIR/
  N=`basename $PRE`
  PRE="chmod a+x /opt/install/$N && sh -c \"/opt/install/$N\""
  PRE_FILE="$N /opt/install/"
else
  PRE_FILE=
fi

if [ -f "$SCRIPT" ]; then
  cp $SCRIPT $WORK_DIR/
  N=`basename $SCRIPT`
  SCRIPT="chmod a+x /opt/install/$N && sh -c \"/opt/install/$N\""
  SCRIPT_FILE="$N /opt/install/"
else
  SCRIPT_FILE=
fi

echo "Creating Singularity definition file $NAME into $FILE"
dd status=none of=${FILE} << EOF
# created by $0 on $DATE
#
# Singularity/Apptainer image $NAME
#
# build: apptainer build $NAME.sif
# run:   apptainer run   $NAME.sif

Bootstrap: docker
From: $FROM

%files
    apt/  /opt/install/
    README /opt/install/
    file_list.txt /opt/install/
    $NAME.def /opt/install/
    $PRE_FILE
    $SCRIPT_FILE

%post
    $PRE
    apt-get update -y
    apt-get install -y --no-install-recommends bash $DEB
    $UUID
    $SCRIPT
    rm -rf /opt/install/apt
    useradd -ms /bin/bash user
    
%environment
    export LC_ALL=C
    export PATH=/usr/games:$PATH

%runscript
    echo "Starting container $NAME, built on $DATE from $FROM"
    cat /opt/install/README || echo " "
    if [ \$# -ge 1 ]; then $CMD $cmd_arg \$@;  else $CMD; fi
    
%help
    This is a $NAME Singularity/Apptainer with packages $@.
    The default start-up command is $CMD.
    Installation files and README are in /opt/install
    
%labels
    Name $NAME
    System $FROM
    Date $DATE
    Creator $0
    Command $CMD
EOF

# build image ------------------------------------------------------------------
FILE=$WORK_DIR/build
dd status=none of=${FILE} << EOF
#!/bin/bash
# created by $0 on $DATE
# $ARGS
#
# build image $NAME with
#
# Usage: build

apptainer build $NAME.sif $NAME.def

# handle of Desktop launchers
mkdir -p launchers/
mkdir -p icons/

# get .desktop files ----------------------------------------------------------
D=\$(grep '\.desktop' file_list.txt) || echo "WARNING: No desktop file found."
# get the desktop files
D=\$(echo "\$D" | awk '{ print \$6 }')

# we need to copy them back, as well as their icons, and change the Exec lines
for i in \$D; do
  if [ \${i:0:1} == "." ] ; then
    i=\$(echo "\$i" | cut -c 2-)
  fi
  n=\`basename \$i\`
  apptainer exec $NAME.sif cat \$i >> launchers/\$n || echo "WARNING: Failed to get desktop launcher \$i"
done

# get icon files --------------------------------------------------------------
D=\$(grep 'icon' file_list.txt) || echo "WARNING: No icon file found."
# get the icon files
D=\$(echo "\$D" | awk '{ print \$6 }')

# we need to copy the icon files back
for i in \$D; do
  if [ \${i:0:1} == "." ] ; then
    i=\$(echo "\$i" | cut -c 2-)
  fi
  n=\`basename \$i\`
  apptainer exec $NAME.sif cp \$i /tmp/$n  &> /dev/null || n= 
  if [ -f "/tmp/\$n" ]; then
    mv /tmp/\$n icons/\$n
  fi
done

# adapt the Desktop launchers to insert 'run', set Icons=
for i in launchers/*; do
  if [ ! -f "\$i" ]; then continue; fi
  I=\$(grep 'Icon=' \$i | cut -d = -f 2) || I=
  if [ ! -z "\$I" ]; then
    n=\`basename \$I\`
    if [ ! -f "icons/\$n" ]; then
      # get closest file that match Icon name when initial name is not present as a file
      n1=( $icons/\$n* ) || n1=
      if [ ! -z "\$n1" ]; then
        n=\`basename \${n1[0]}\`
      fi
    fi
    sed -i "s|Icon=.*|Icon=icons/\$n|g" \$i            || echo " "
  fi
  sed -i 's|Exec=|&$cmd $cmd_arg |g' \$i        || echo " "
  sed -i 's|Terminal=false|Terminal=true|g' \$i || echo " "
  chmod a+x \$i                                 || echo " "
done

# create a Terminal launcher
echo "[Desktop Entry]"       > launchers/$NAME-terminal.desktop
echo "Type=Application"     >> launchers/$NAME-terminal.desktop
echo "Name=$NAME Terminal"  >> launchers/$NAME-terminal.desktop
echo "Terminal=true"        >> launchers/$NAME-terminal.desktop
echo "Exec=$cmd"            >> launchers/$NAME-terminal.desktop
chmod a+x                      launchers/$NAME-terminal.desktop

EOF

chmod a+x $WORK_DIR/build

if [ "x$BUILD" = "x1" ]; then
  # build the image
  (cd $WORK_DIR && ./build)
  chmod a+x $WORK_DIR/$NAME.sif || exit
else
  echo "INFO: To build this image, use: cd $WORK_DIR; ./build"
  echo " "
  cat $WORK_DIR/build
fi

# ------------------------------------------------------------------------------
# get executables and Desktop launchers (from the container)
echo "------------------------------------------------------" >> $WORK_DIR/README
B=$(grep '\.desktop' $WORK_DIR/file_list.txt) || echo " "
echo "$B"                                                     >> $WORK_DIR/README

FILE=$WORK_DIR/start
dd status=none of=${FILE} << EOF
#!/bin/bash
# created by $0 on $DATE
# $ARGS
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
echo "To start $NAME, use any of: "
echo "  cd $WORK_DIR; ./$NAME.sif [cmd]"
echo "  cd $WORK_DIR; ./start     [cmd]"
echo " "
