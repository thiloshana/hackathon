#!/bin/bash
# --------------------------------------------------------------
#
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.
# --------------------------------------------------------------

# Execute error_handler function on script error
trap 'error_handler ${LINENO} $?' ERR

shopt -s nocasematch
ECHO=`which echo`
RM=`which rm`
TR=`which tr`
HEAD=`which head`
WGET=`which wget`
MKDIR=`which mkdir`
GREP=`which grep`
SED=`which sed`
CP=`which cp`
MV=`which mv`
SLEEP=`which sleep`
ID=`which id`

VERBOSE=""
TIMESYNC=""

HOSTSFILE=/etc/hosts
DATE=`date +%d%m%y%S`
RANDOMNUMBER="`${TR} -c -d 0-9 < /dev/urandom | ${HEAD} -c 7`${DATE}"

function error_handler(){
        MYSELF="$0"               # equals to script name
        LASTLINE="$1"            # argument 1: last line of error occurence
        LASTERR="$2"             # argument 2: error code of last command
        echo "ERROR in ${MYSELF}: line ${LASTLINE}: exit status of last command: ${LASTERR}"
	exit 1       
}

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function print_error(){
	if [ "${VERBOSE}" = "-v" ]; then
    		${ECHO} -e " [Error]\n"$1
	else
    		${ECHO} -e "[Error]" $1
	fi
	exit 1
}

function print_message(){
	if [ "${VERBOSE}" = "-v" ]; then
    		${ECHO} -e $1
	fi    
}

function print_ok(){
	if [ "${VERBOSE}" = "-v" ]; then
    		${ECHO} -e " [Done]"  	 
	fi
}

function check_user(){
# Check for root
	print_message "Checking for user permission ... "
	if [ `${ID} -u` != 0 ] ; then
    		print_error "Need root access.\nRun the script as 'root' or with 'sudo' permissions. "
	else
    		print_ok
	fi
}

#Load setup configuration
source "/root/bin/setup.conf"

# Check all input parameters.
while getopts ":vynd:m:s: --verbose --nosync --yes --domain --masterip --servicename" opt; do
	case ${opt} in    	
    	v|--verbose)
        	VERBOSE="-v"
        	;;    	
    	n|--nosync)
        	TIMESYNC="-N"
        	;;
    	d|--domain)
        	DOMAIN=${OPTARG}
        	;;
    	m|--masterip)
        	MASTERIP=${OPTARG}
        	;;
    	s|--servicename)
        	SERVICE_NAME=${OPTARG}
        	;;
    	y|--yes)
        	ASSUME_YES=1
        	;;
     	\?)
        	${ECHO} -e "config: Invalid option: -${OPTARG}"        	
        	exit 1
        	;;
	esac
done

if [[ -z $ASSUME_YES ]] ; then

	while true; do
	    read -p "This script will install and configure puppet agent, do you want to continue [y/n]" answer
	    case $answer in
		[Yy]* ) break;;
		[Nn]* ) exit;;
		* ) echo "Please answer yes or no.";;
	    esac
	done
fi

# Validate the user
check_user

${CP} -f ${HOSTSFILE} /etc/hosts.tmp
${MKDIR} -p /tmp/payload
#${WGET} http://169.254.169.254/latest/user-data -O /tmp/payload/launch-params

if [[ -z $SERVICE_NAME ]]; then
	read -p "Please provide stratos service-name:" SERVICE_NAME
	if [[ -z $SERVICE_NAME ]]; then
		echo "service is empty!. Base image will be created."
		SERVICE_NAME=default
	fi
fi

if [[ -z $MASTERIP ]]; then
	read -p "Please provide puppet master IP:" MASTERIP
	if ! valid_ip $MASTERIP ; then
		echo "invalid IP address format!"
		exit -1
	fi
fi 


if [[ -z $DOMAIN ]]; then
	read -p "Please provide puppet master hostname [puppet.stratos.org]:" DOMAIN
fi

DOMAIN=${DOMAIN:-puppet.stratos.org}
#essential to have PUPPET_HOSTNAME at the end in order to auto-sign the certs

#read -p "Please provide stratos deployment:" DEPLOYMENT
#DEPLOYMENT=${DEPLOYMENT:-default}
DEPLOYMENT="default"

NODEID="${RANDOMNUMBER}.${DEPLOYMENT}.${SERVICE_NAME}"

${ECHO} -e "\n Node Id ${NODEID} \n"
${ECHO} -e "\n Domain ${DOMAIN} \n"

ARGS=("-n${NODEID}" "-d${DOMAIN}" "-s${MASTERIP}" ${VERBOSE} ${TIMESYNC})
${ECHO} -e "\n Running puppet installation with arguments: ${ARGS[@]}"
/root/bin/puppetinstall/puppetinstall "${ARGS[@]}" || print_error "Failed to install Puppet...configuration failed."

PUPPET=`which puppet`
PUPPETAGENT="${PUPPET} agent"
RUNPUPPET="${PUPPETAGENT} -vt"

# Kill puppet agent process and disable auto start
${PUPPET} resource service puppet ensure=stopped enable=false

${PUPPETAGENT} --enable
${RUNPUPPET} || true
${PUPPETAGENT} --disable

${RM} -f /mnt/apache-stratos-cartridge-agent-4.0.0-SNAPSHOT/wso2carbon.lck
${GREP} -q '/root/bin/init.sh > /tmp/puppet_log' /etc/rc.local || ${SED} -i 's/exit 0$/\/root\/bin\/init.sh \> \/tmp\/puppet_log\nexit 0/' /etc/rc.local
${RM} -rf /tmp/*
${RM} -rf /var/lib/puppet/ssl/*
${MV} -f /etc/hosts.tmp ${HOSTSFILE}

${ECHO} -e "\n---------------------------------"
${ECHO} -e "Successfully configured Apache Stratos cartridge instance\n"
# END
