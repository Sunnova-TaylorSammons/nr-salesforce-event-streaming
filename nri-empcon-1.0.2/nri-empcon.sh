#!/bin/sh
# change to #!/bin/ksh or #!/bin/bash

### Set these as appropriate ###

# Change to false if you want to append to existing logs.
# DELETE_LOGS_ON_STARTUP=true

# Uncomment if you are using a JDK packaged with WebSphere
# USE_IBM_JSSE=true

# Uncomment to manually define Plugin path if this script can't find it
# PLUGIN_PATH=/opt/newrelic/unix-infra-monitor

# Uncomment to manually define Java path & filename if this script can't find it
# AIX:
# PLUGIN_JAVA=/usr/java6/bin/java
# LINUX & SOLARIS:
# PLUGIN_JAVA=/usr/bin/java
# OSX / MACOS:
# PLUGIN_JAVA=/Library/Java/JavaVirtualMachines/<version>/Contents/Commands/java

#
# Set to the value of your obfuscation key
# Either directly as the key, or indirectly as another environment variable
# NEW_RELIC_CONFIG_OBSCURING_KEY=your_key_or_envvar_here

### Do not change these unless instructed! ###

PLUGIN_NAME="New Relic EMPCon"

# Behavior when "start" command is issued and plugin is running
# False (default): Plugin will not be restarted.
# True: Plugin will be restarted.
PLUGIN_RESTART_ON_START=false

# Attempt to set plugin path if not manually defined above
if [ -z "$PLUGIN_PATH" ]; then
  RELATIVE_PATH=`dirname "$0"`
  PLUGIN_PATH=`eval "cd \"$RELATIVE_PATH\" && pwd"`
fi
echo "Plugin location: $PLUGIN_PATH"

# Comment-out if using -jar
PLUGIN_JAVA_CLASS=com.newrelic.fit.empcon.Main
# Set to the jar if using -jar
PLUGIN_JAVA_CLASSPATH="$PLUGIN_PATH/lib/nri-empcon.jar"
PLUGIN_JAVA_OPTS="-Xms16m -Xmx128m"

# Attempt to set Java path & filename if not manually defined above
if [ -z "$PLUGIN_JAVA" ]; then
  if [ -n "$JAVA_HOME" ]; then
    PLUGIN_JAVA=$JAVA_HOME/bin/javacd 
  else
    PLUGIN_JAVA=`which java`
  fi
  # If attempt to set Java path & filename failed, throw error
  if [ -z "$PLUGIN_JAVA" ]; then
    echo "Could not find Java and is not manually defined."
    echo "Please edit pluginctl.sh and set PLUGIN_JAVA to a valid Java binary."
    exit 1
  fi
fi

PLUGIN_HOST_OS=`uname`

if [ "$PLUGIN_HOST_OS" = "SunOS" ]; then
  AWK_COMMAND="nawk"
else
  AWK_COMMAND="awk"
fi

PLUGIN_JAVA_VERSION_FULL=`$PLUGIN_JAVA -Xmx32m -version 2>&1`
PLUGIN_JAVA_VERSION=`echo $PLUGIN_JAVA_VERSION_FULL | $AWK_COMMAND -F '"' '/version/ {print $2}'`
# Old versions of Java are written as "1.x", Newer versions of Java are written as "x".
PLUGIN_JAVA_MAJOR_VERSION=`echo $PLUGIN_JAVA_VERSION | $AWK_COMMAND '{ split($0, array, ".") } END{ print (array[1] == 1) ? array[2] : array[1] }'`

echo "Java location: $PLUGIN_JAVA"
echo "Java version: $PLUGIN_JAVA_VERSION"
echo "Java major version: $PLUGIN_JAVA_MAJOR_VERSION"

if [ $PLUGIN_JAVA_MAJOR_VERSION -lt 6 ]; then
  echo "ERROR: $PLUGIN_NAME will not work with Java versions older than 1.6."
  echo "Please edit pluginctl.sh and set PLUGIN_JAVA to a Java distro (Sun/Oracle, IBM, OpenJDK) v1.6 or above."
  exit 1
fi

if [ `echo $PLUGIN_JAVA_VERSION_FULL | grep -c -i 'gcj'` -gt 0 ]; then
  echo "ERROR: $PLUGIN_NAME will not work with gcj."
  echo "Please edit pluginctl.sh and set PLUGIN_JAVA to another Java distro (Sun/Oracle, IBM, OpenJDK)."
  echo "Output of \"java -version\":\n $PLUGIN_JAVA_VERSION_FULL"
  exit 1
fi

PLUGIN_ERR_FILE=$PLUGIN_PATH/logs/plugin.err
PLUGIN_LOG_FILE=$PLUGIN_PATH/logs/plugin.log
PLUGIN_PID_FILE=$PLUGIN_PATH/logs/plugin.pid

# Added for IBM JSSE support
if [ -n "$USE_IBM_JSSE" ] && [ "$USE_IBM_JSSE" = "true" ]; then
  PLUGIN_SEC_FILE=$PLUGIN_PATH/etc/ibm_jsse.java.security
  echo "Using IBM JSSE, classes defined in $PLUGIN_SEC_FILE"
  PLUGIN_JAVA_OPTS="$PLUGIN_JAVA_OPTS -Djava.security.properties=$PLUGIN_SEC_FILE"
fi

if [ -n "$PLUGIN_JAVA_CLASS" ]; then
  PLUGIN_JAVA_FULL_COMMAND="$PLUGIN_JAVA $PLUGIN_JAVA_OPTS -cp $PLUGIN_JAVA_CLASSPATH $PLUGIN_JAVA_CLASS"
else
  PLUGIN_JAVA_FULL_COMMAND="$PLUGIN_JAVA $PLUGIN_JAVA_OPTS -jar $PLUGIN_JAVA_CLASSPATH"
fi

check_plugin_status() {
  echo ""
  echo "Checking $PLUGIN_NAME"
  if [ -f $PLUGIN_PID_FILE ]; then
    PID=`cat $PLUGIN_PID_FILE`
    if [ -z "`ps -ef | grep ${PID} | grep -v grep`" ]; then
      echo "Process dead but $PLUGIN_PID_FILE exists"
      echo "Deleting $PLUGIN_PID_FILE"
      rm -f $PLUGIN_PID_FILE
      procstatus=0
    else
      echo "$PLUGIN_NAME is running with PID $PID"
      procstatus=1
    fi
  else
    echo "$PLUGIN_NAME is not running"
    procstatus=0
  fi
  return "$procstatus"
}

stop_plugin() {
  check_plugin_status
  procstatus=$?
  if [ "$procstatus" -eq 1 ] && [ -f $PLUGIN_PID_FILE ]; then
    echo "Stopping $PLUGIN_NAME" | tee -a $PLUGIN_ERR_FILE
    PID=`cat $PLUGIN_PID_FILE`
    kill -TERM $PID
    echo "$PLUGIN_NAME running with PID $PID stopped" | tee -a $PLUGIN_ERR_FILE
    rm -f $PLUGIN_PID_FILE
  else
    echo "$PLUGIN_NAME is not running or $PLUGIN_PID_FILE not found"
  fi
}

start_plugin() {
  mkdir -p $PLUGIN_PATH/logs
  check_plugin_status
  procstatus=$?
  if [ "$procstatus" -eq 1 ]; then
    if [ "$PLUGIN_RESTART_ON_START" = "false" ]; then
      echo "Plugin is already running, restart will not occur"
      exit 2
      elif [ "$PLUGIN_RESTART_ON_START" = "true" ]; then
      echo "Restarting $PLUGIN_NAME"
      stop_plugin
    else
      echo "Plugin is already running, restart will not occur"
      exit 2
    fi
  fi

  if [ "$DELETE_LOGS_ON_STARTUP" = true ] ; then
    echo "Deleting logs"
    rm -f $PLUGIN_ERR_FILE
    rm -f $PLUGIN_LOG_FILE
  fi

  echo "####################" >> $PLUGIN_ERR_FILE
  echo "Starting $PLUGIN_NAME" | tee -a $PLUGIN_ERR_FILE
  echo "Host OS: $PLUGIN_HOST_OS" >> $PLUGIN_ERR_FILE
  echo "Java location: $PLUGIN_JAVA" >> $PLUGIN_ERR_FILE
  echo "Java version: $PLUGIN_JAVA_VERSION_FULL" >> $PLUGIN_ERR_FILE
  echo "Plugin location: $PLUGIN_PATH" >> $PLUGIN_ERR_FILE
  echo "Plugin startup command: $PLUGIN_JAVA_FULL_COMMAND" >> $PLUGIN_ERR_FILE

  nohup $PLUGIN_JAVA_FULL_COMMAND >/dev/null 2>>$PLUGIN_ERR_FILE &
  PID=`echo $!`
  if [ -z $PID ]; then
    echo "$PLUGIN_NAME failed to start" | tee -a $PLUGIN_ERR_FILE
    echo "####################" >> $PLUGIN_ERR_FILE
    exit 1
  else
    echo $PID > $PLUGIN_PID_FILE
    echo "$PLUGIN_NAME started with PID $PID" | tee -a $PLUGIN_ERR_FILE
    echo "####################" >> $PLUGIN_ERR_FILE
    exit 0
  fi
}



case "$1" in
  status)
    check_plugin_status
  ;;
  start)
    start_plugin
  ;;
  restart)
    echo "Restarting $PLUGIN_NAME."
    stop_plugin
    start_plugin
  ;;
  stop)
    stop_plugin
  ;;
  stopremlogs)
    stop_plugin
    echo "Clearing plugin logs."
    rm -f $PLUGIN_PATH/logs/*
  ;;
  *)
    echo "Usage: $0 [status|start|stop|stopremlogs|restart]"
    exit 1
esac
