#!/bin/bash

## Important Notes: 
## [1] This is custom script and not part of product. Please test the script in development cluster, make necessary changes and deploy in production cluster.
##
##
## [2] Please make sure the 'sqlline' login command used in this script is working as expected in your cluster as well.
## 	sqlline -u "jdbc:drill:zk=${Z_QOURUM}" -n ${uname} -p ${password} 
## [3] Zookeeper quorum list is obtained using: maprcli node listzookeepers

## Setting the script home directory.
## Please create the directory and copy the files to the same.
## By default the location is : /tmp/DOY_AUTO_RESTART
DOY_SCRIPT_HOME=/tmp/DOY_AUTO_RESTART
if [ -d ${DOY_SCRIPT_HOME} ]
then
	echo "`date` [INFO] Starting script execution........" >> ${DOY_SCRIPT_HOME}/doy_auto_restart.log 2>&1
	echo "`date` [INFO] Script home directory set to: "${DOY_SCRIPT_HOME} >> ${DOY_SCRIPT_HOME}/doy_auto_restart.log 2>&1
else
	echo "[ERROR] ${DOY_SCRIPT_HOME} not present. Please create the directory with necessary files. (hostnames, credentials)" 
	echo "[ERROR]Aborting the script." 
	exit 1
fi

cd ${DOY_SCRIPT_HOME}

## Check if '${DOY_SCRIPT_HOME}/hostnames' file is present.
## 'hostnames' file contain list of all the hostnames where drillbit can run.
if [ -f "hostnames" ]; then
	echo "`date` [INFO] hostnames files loaded." >> doy_auto_restart.log 2>&1
else
	echo "[ERROR]hostnames file not found. Please create 'hostnames' file containing all the hostnames." 
	echo "[ERROR]Aboring the script."
	exit 1;
fi

## Loading the credentials from '${DOY_SCRIPT_HOME}/credentials' property file.
## Provide mapr username (uname), mapr password (password) and drill port information inside a file 'credentials' in the script home.
## By default port will be 8047.
file="credentials"
if [ -f "$file" ]
then
	while IFS='=' read -r key value
	do
		eval "${key}='${value}'"
	done < "$file"
else
	echo "[ERROR] $file file not found." 
	echo "[ERROR] Aboring the script."  
	exit 1;
fi

## Checking for necessary information in credentials file.
## Following details are required.
## uname=<username for mapr user>
## password=<password of mapr user>
## check_plugin=<plugin to check whether it is enabled> Eg: hive,dfs,hbase. (Your case check put 'hive'.)
## stop_doy_command=<DRILL stop command> Eg: /opt/mapr/drill/drill-1.10.0/bin/drill-on-yarn.sh --site $DRILL_SITE stop
## start_doy_command=<DRILL start command> Eg: /opt/mapr/drill/drill-1.10.0/bin/drill-on-yarn.sh --site $DRILL_SITE start
if [ -z "${uname}" ]
then
	echo "[ERROR] Username not found. Please provide uname in '${DOY_SCRIPT_HOME}/credentials' file"
	echo "[ERROR] Aborting the script."
	exit 1;
fi
if [ -z "${password}" ]
then
	echo "[ERROR] Password not found. Please provide password in '${DOY_SCRIPT_HOME}/credentials' file" 
	echo "[ERROR] Aborting the script."  
	exit 1;
fi
if [ -z "${port}" ]
then
	echo "`date` [WARN] Drill port not found. Setting to default value of 8047."  >> doy_auto_restart.log 2>&1
	port=8047
fi
if [ -z "${check_plugin}" ]
then
        echo "[ERROR] 'check_plugin' not found. Please provide 'check_plugin' in '${DOY_SCRIPT_HOME}/credentials' file"
        echo "[ERROR] Aborting the script."
        exit 1;
fi
if [ -z "${stop_doy_command}" ]
then
        echo "[ERROR] stop_doy_command not found. Please provide stop_doy_command in '${DOY_SCRIPT_HOME}/credentials' file"
        echo "[ERROR] Aborting the script."
        exit 1;
fi
if [ -z "${start_doy_command}" ]
then
        echo "[ERROR] start_doy_command not found. Please provide start_doy_command in '${DOY_SCRIPT_HOME}/credentials' file"
        echo "[ERROR] Aborting the script."
        exit 1;
fi

if [ -d plugins ]
then
        echo "`date` [INFO] Plugins directory found." >> doy_auto_restart.log 2>&1
else
        echo "[ERROR] Plugins not present. Please create the directory with necessary plugin files."
        echo "[ERROR]Aborting the script."
        exit 1
fi


## Obtaining the Zookeeper qourum list.
Z_QOURUM=$(maprcli node listzookeepers | grep -v "Zookeepers")
if [[ -n "$Z_QOURUM" ]]; then 
	echo "`date` [INFO] List of Zookeepers in the cluster: "${Z_QOURUM}   >> doy_auto_restart.log 2>&1
	
	## DOY cluster will be restarted if 'hive' plugin is missing. (This is as per your use case.)
	echo "`date` [INFO] Checking whether ${check_plugin} plugin is available in the cluster."  >> doy_auto_restart.log 2>&1
	sqlline -u "jdbc:drill:zk=${Z_QOURUM}" -n ${uname} -p ${password} -e "show schemas;" | grep ${check_plugin}


## Restarting the DOY cluster.
if [ $? -ne 0 ]; then
	echo "`date` [WARN] ${check_plugin} storage plugin missing. Restarting the cluster."  >> doy_auto_restart.log 2>&1
	
	## Stopping the existing cluster.
	echo "`date` [INFO] Stopping DOY cluster. Command used: $stop_doy_command" >> doy_auto_restart.log 2>&1
	$stop_doy_command
	sleep 5
	echo "`date` [INFO] Sleeping for 5 seonds." >> doy_auto_restart.log 2>&1
	
	## Starting a DOY cluster.
	echo "`date` [INFO] Starting DOY cluster. Command used: $start_doy_command" >> doy_auto_restart.log 2>&1
	$start_doy_command
	echo "`date` [INFO] Sleeping for 120 seonds. Waiting for cluster to come up." >> doy_auto_restart.log 2>&1
	sleep 120

	## Loading the cookies.
	## This is required for drill clusters with authentication.
	## Cookies will be stored inside '${DOY_SCRIPT_HOME}/cookies' folder.
	## Assumption is the cookies for all the hosts will be availabe if '${DOY_SCRIPT_HOME}/cookies' folder is present. Else it will be regenerated.
	if [ -d "cookies" ]; then
		echo "`date` [INFO] Cookies folder present."  >> doy_auto_restart.log 2>&1
		echo "`date` [INFO] Removing the cookies folder." >> doy_auto_restart.log 2>&1
		rm -rf cookies
		
		echo "`date` [INFO] Generating new cookies." >> doy_auto_restart.log 2>&1
		mkdir cookies
		cat hostnames | while read host
                do
                        echo "`date` [INFO] Loading cookie for host: "${host}  >> doy_auto_restart.log 2>&1
                        curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -k -c cookies/cookies_${host}.txt -s -d "j_username=${uname}" -d "j_password=${password}" http://${host}:${port}/j_security_check
                done
	else
        	echo "`date` [INFO] Cookies folder missing. Generating cookies."  >> doy_auto_restart.log 2>&1
	        mkdir cookies
	        cat hostnames | while read host
	        do
        	        echo "`date` [INFO] Loading cookie for host: "${host}  >> doy_auto_restart.log 2>&1
                	curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -k -c cookies/cookies_${host}.txt -s -d "j_username=${uname}" -d "j_password=${password}" http://${host}:${port}/j_security_check
	        done
	fi
	

	
	echo "`date` [INFO] Starting to update the plugin. Polling different drillbit nodes." >> doy_auto_restart.log 2>&1
	while read host
	do 
		plugin_creation_success="true"
                for plugin in `ls -1 plugins`
		do
			echo "`date` [INFO] Trying to update ${plugin} plugin by polling drillbit on ${host}."  >> doy_auto_restart.log 2>&1
			curl -k -b cookies/cookies_${host}.txt -X POST -H "Content-Type: application/json" -d @plugins/${plugin} http://${host}:${port}/storage/${plugin} | grep "success"
		if [ $? -eq 0 ]; then
			echo "`date` [INFO] Successfully updated ${plugin}."  >> doy_auto_restart.log 2>&1
		else
			echo "`date` [WARN] Could not update ${plugin} plugin by polling drillbit on ${host}. Seems like drillbit is not up and running on this node."  >> doy_auto_restart.log 2>&1
		plugin_creation_success="false"
		fi
		done
		
		if [ "$plugin_creation_success" == "true" ] ; then
			echo "`date` [INFO] Successfully created all the plugins." >> doy_auto_restart.log 2>&1
			echo "`date` [INFO] Skipping plugin creation with other hosts." >> doy_auto_restart.log 2>&1
	                break
                fi

	done < hostnames
echo "`date` [INFO] Script successfully completed."  >> doy_auto_restart.log 2>&1
else
	echo "[INFO] Plugin ${check_plugin} available. Cluster looks healthy."  >> doy_auto_restart.log 2>&1
	echo "[INFO] Script execution completed." >> doy_auto_restart.log 2>&1
fi
else 
	echo "[ERROR] Unable to contact Zookeepers. Aborting the script."
fi

