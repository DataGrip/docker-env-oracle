#!/bin/bash
# LICENSE CDDL 1.0 + GPL 2.0
#
# Copyright (c) 1982-2016 Oracle and/or its affiliates. All rights reserved.
# 
# Since: November, 2016
# Author: gerald.venzl@oracle.com
# Description: Runs the Oracle Database inside the container
# 
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
# 

########### Move DB files ############
function moveFiles {

   if [ ! -d $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID ]; then
      mkdir -p $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/
   fi;

   mv $ORACLE_HOME/dbs/spfile$ORACLE_SID.ora $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/
   mv $ORACLE_HOME/dbs/orapw$ORACLE_SID $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/
   mv $ORACLE_HOME/network/admin/tnsnames.ora $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/

   # oracle user does not have permissions in /etc, hence cp and not mv
   cp /etc/oratab $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/
   
   symLinkFiles;
}

########### Symbolic link DB files ############
function symLinkFiles {

   if [ ! -L $ORACLE_HOME/dbs/spfile$ORACLE_SID.ora ]; then
      ln -s $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/spfile$ORACLE_SID.ora $ORACLE_HOME/dbs/spfile$ORACLE_SID.ora
   fi;
   
   if [ ! -L $ORACLE_HOME/dbs/orapw$ORACLE_SID ]; then
      ln -s $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/orapw$ORACLE_SID $ORACLE_HOME/dbs/orapw$ORACLE_SID
   fi;
   
   if [ ! -L $ORACLE_HOME/network/admin/tnsnames.ora ]; then
      ln -s $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/tnsnames.ora $ORACLE_HOME/network/admin/tnsnames.ora
   fi;

   # oracle user does not have permissions in /etc, hence cp and not ln 
   cp $ORACLE_BASE/oradata/dbconfig/$ORACLE_SID/oratab /etc/oratab

}

########### SIGINT handler ############
function _int() {
   echo "Stopping container."
   echo "SIGINT received, shutting down database!"
   sqlplus / as sysdba <<EOF
   shutdown immediate;
   exit;
EOF
   lsnrctl stop
}

########### SIGTERM handler ############
function _term() {
   echo "Stopping container."
   echo "SIGTERM received, shutting down database!"
   sqlplus / as sysdba <<EOF
   shutdown immediate;
   exit;
EOF
   lsnrctl stop
}

########### SIGKILL handler ############
function _kill() {
   echo "SIGKILL received, shutting down database!"
   sqlplus / as sysdba <<EOF
   shutdown abort;
   exit;
EOF
   lsnrctl stop
}

########### Disable ASYNCH_IO ############
function disable_asynch_io {
   echo "Disable ASYNCH_IO"
   sqlplus / as sysdba <<EOF
   ALTER SYSTEM SET FILESYSTEMIO_OPTIONS=DIRECTIO SCOPE=SPFILE
   /
   ALTER SYSTEM SET DISK_ASYNCH_IO=FALSE SCOPE=SPFILE
   /
EOF
   sqlplus / as sysdba << EOF
   SHUTDOWN;
   exit;
EOF
   sqlplus / as sysdba << EOF
   STARTUP;
   exit;
EOF
}

########### Create test user ############
function createTestUser {
  # Auto generate ORACLE TEST USER if not passed
  export ORACLE_TEST_USER=${ORACLE_TEST_USER:-"c##tester"}
  echo "ORACLE TEST USER: $ORACLE_TEST_USER";

  # Auto generate ORACLE TEST PWD if not passed
  export ORACLE_TEST_PWD=${ORACLE_TEST_PWD:-"testpwd"}
  echo "ORACLE TEST PWD FOR ORACLE_TEST_USER: $ORACLE_TEST_PWD";

 	cat <<-EOF > create-user.sql
        ALTER SESSION SET "_ORACLE_SCRIPT"=true;  
				DECLARE
				  user_exists INTEGER := 0;
				BEGIN
				  SELECT COUNT(1) INTO user_exists FROM dba_users WHERE username = UPPER('$ORACLE_TEST_USER');
				  IF user_exists = 0
				  THEN
				    EXECUTE IMMEDIATE ('CREATE USER $ORACLE_TEST_USER IDENTIFIED BY $ORACLE_TEST_PWD');
				    EXECUTE IMMEDIATE ('GRANT ALL PRIVILEGES TO $ORACLE_TEST_USER');
				    EXECUTE IMMEDIATE ('GRANT SELECT ANY DICTIONARY TO $ORACLE_TEST_USER');
				  END IF;
				END;
				/
        exit;
			EOF

  sqlplus / as sysdba @./create-user.sql 
}

############# Run init sql scripts (shipped) ################
function runInitScripts {  
  echo "Running predefined sys-init.sql & create-test-user.sql files"
  
  # Adding exit; for sqlplus correct execution;
  echo "exit;" >> $ORACLE_BASE/sys-init.sql
  echo "exit;" >> $ORACLE_BASE/create-test-users.sql

  sqlplus / as sysdba @$ORACLE_BASE/sys-init.sql
  sqlplus / as sysdba @$ORACLE_BASE/create-test-users.sql
}

###################################
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
############# MAIN ################
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
###################################

# Check whether container has enough memory
# Github issue #219: Prevent integer overflow,
# only check if memory digits are less than 11 (single GB range and below) 
if [ `cat /sys/fs/cgroup/memory/memory.limit_in_bytes | wc -c` -lt 11 ]; then
   if [ `cat /sys/fs/cgroup/memory/memory.limit_in_bytes` -lt 2147483648 ]; then
      echo "Error: The container doesn't have enough memory allocated."
      echo "A database container needs at least 2 GB of memory."
      echo "You currently only have $((`cat /sys/fs/cgroup/memory/memory.limit_in_bytes`/1024/1024/1024)) GB allocated to the container."
      exit 1;
   fi;
fi;

# Set SIGINT handler
trap _int SIGINT

# Set SIGTERM handler
trap _term SIGTERM

# Set SIGKILL handler
trap _kill SIGKILL

# Default for ORACLE SID
if [ "$ORACLE_SID" == "" ]; then
   export ORACLE_SID=ORCLCDB
else
  # Check whether SID is no longer than 12 bytes
  # Github issue #246: Cannot start OracleDB image
  if [ "${#ORACLE_SID}" -gt 12 ]; then
     echo "Error: The ORACLE_SID must only be up to 12 characters long."
     exit 1;
  fi;
  
  # Check whether SID is alphanumeric
  # Github issue #246: Cannot start OracleDB image
  if [[ "$ORACLE_SID" =~ [^a-zA-Z0-9] ]]; then
     echo "Error: The ORACLE_SID must be alphanumeric."
     exit 1;
   fi;
fi;

# Default for ORACLE PDB
export ORACLE_PDB=${ORACLE_PDB:-ORCLPDB1}

# Default for ORACLE CHARACTERSET
export ORACLE_CHARACTERSET=${ORACLE_CHARACTERSET:-AL32UTF8}

# Check whether database already exists
if [ -d $ORACLE_BASE/oradata/$ORACLE_SID ]; then
   symLinkFiles;
   
   # Make sure audit file destination exists
   if [ ! -d $ORACLE_BASE/admin/$ORACLE_SID/adump ]; then
      mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/adump
   fi;
   
   # Start database
   $ORACLE_BASE/$START_FILE;
   
   # todo: add create user and run *.sql file
else
   # Remove database config files, if they exist
   rm -f $ORACLE_HOME/dbs/spfile$ORACLE_SID.ora
   rm -f $ORACLE_HOME/dbs/orapw$ORACLE_SID
   rm -f $ORACLE_HOME/network/admin/tnsnames.ora
   
   # Create database
   $ORACLE_BASE/$CREATE_DB_FILE $ORACLE_SID $ORACLE_PDB $ORACLE_PWD;
   
   # Move database operational files to oradata
   moveFiles;
fi;

# Check whether database is up and running
$ORACLE_BASE/$CHECK_DB_FILE
if [ $? -eq 0 ]; then
  disable_asynch_io;

  echo "Creating test user"
  createTestUser;

  echo "Running init scripts" 
  runInitScripts;

  echo "#########################"
  echo "DATABASE IS READY TO USE!"
  echo "#########################"
else
   echo "#####################################"
   echo "########### E R R O R ###############"
   echo "DATABASE SETUP WAS NOT SUCCESSFUL!"
   echo "Please check output for further info!"
   echo "########### E R R O R ###############" 
   echo "#####################################"
fi;

# Tail on alert log and wait (otherwise container will exit)
echo "The following output is now a tail of the alert.log:"
tail -f $ORACLE_BASE/diag/rdbms/*/*/trace/alert*.log &
childPID=$!
wait $childPID
