#/bin/bash
current_path=`dirname $0`
. ${current_path}/pgmonitor.conf
. ~/.bash_profile
hostname=`hostname`

OLD_IFS=$IFS

#$1 监控项，$2信息内容
function callsendms(){
	ssh -p ${SSHPORT} $MSUSER@$MSHOST "cat ${REMODIR}/phone |grep ${hostname}|grep ${PUBIP}|grep $1 > ${REMODIR}/tmp/phone#${hostname}#${PUBIP}#$1.tmp" #生成临时文件
	# echo "${REMODIR}/phone ${hostname} ${PUBIP} $1 ${REMODIR}/tmp/phone#${hostname}#$1.tmp"
	ssh -p ${SSHPORT} $MSUSER@$MSHOST "sh ${REMODIR}/pgsendms.sh ${hostname} ${PUBIP} \"$2\" ${REMODIR}/tmp/phone#${hostname}#${PUBIP}#$1.tmp" #执行远程shell发送短信
	# echo "${REMODIR}/pgsendms.sh \"$2\" ${REMODIR}/tmp/phone#${hostname}#$1.tmp"
	ssh -p ${SSHPORT} $MSUSER@$MSHOST "rm -f ${REMODIR}/tmp/phone#${hostname}#${PUBIP}#$1.tmp"
}
#设置计数器，控制各项监控频率
if [[ ! -f dbcounters.tmp ]]; then
	echo 0 > ${current_path}/dbcounters.tmp
	counter=0
else
	counter=`cat ${current_path}/dbcounters.tmp`
	#statements
fi

#备份告警
if [[ -f ${current_path}/backupflag && ${BACK_STAT_MON} == "Y" ]]; then
	ms_info=`cat ${current_path}/backupflag`
	if [[ ${ms_info} =~ "successful" ]]; then
		callsendms back_stat "${ms_info}"
		rm -f ${current_path}/backupflag
	elif [[ $(( ${counter} % ${BACK_STAT_PER} )) == 0 ]]; then
		callsendms back_stat "${ms_info}"
	fi
fi

###是否存活
is_alive=`pg_isready -p ${DBPORT}|grep "accepting"|wc -l `
if [[ $is_alive -eq 0 ]]; then
	ms_info="isalive: database is down"
	callsendms is_alive "${ms_info}"
else
	###判断主从
	is_recovery=`psql -t -c "SELECT pg_is_in_recovery();"`

	# echo "pg is ok"
	#链接数
	if [[ ${CONN_NUM_MON} == "Y" && $(( ${counter} % ${CONN_NUM_FRE} )) == 0 ]]; then
		IFS=$'\n'
		for line  in `psql -t -q -c "select datname,numbackends from pg_stat_database where datname is not null;"`;do
			db_name=`echo $line|awk -F "|" '{print $1}'`
			conn_num=`echo $line|awk -F "|" '{print $2}'`
			if [[ ${conn_num} -ge ${CONN_NUM_ALERT} ]]; then
				ms_info="Database :(${db_name}) number of connections: ${conn_num}"
				callsendms conn_num "${ms_info}"
			fi
		done
		IFS=$OLD_IFS
		# echo ${conn_num}
	fi
	#等待事件
	if [[ ${WAIT_NUM_MON} == "Y" && $(( ${counter} % ${WAIT_NUM_PRE} )) == 0 ]]; then
		IFS=$'\n'
		for line in `psql -t -c "select wait_event,count(*) from pg_stat_activity where wait_event is not null and wait_event not in ('ClientRead') group by wait_event;"`; do
			wait_name=`echo $line|awk -F "|" '{print $1}'`
			wait_count=`echo $line|awk -F "|" '{print $2}'`
			if [[ ${wait_count} -ge ${WAIT_NUM_ALERT} ]]; then
				ms_info="Wait event: ${wait_name} ${wait_count}"
				callsendms wait_num "${ms_info}"
			fi
			# echo ${wait_name} ${wait_count} 
		done
		IFS=$OLD_IFS
	fi
	#备库查看事务延迟
	# if [[ ${is_recovery} =~ "t" && ${DELAY_MON} == "Y" && $(( ${counter} % ${DELAY_PRE} )) == 0 ]]; then
	# 	delay_time=`psql -t -c "select trunc(extract(epoch from now() - pg_last_xact_replay_timestamp()));"`
	# 	if [[ ${delay_time} -ge ${DELAY_ALERT} ]]; then
	# 		ms_info="Delay time: ${delay_time} (second)"
	# 		callsendms delay_time "${ms_info}"
	# 	fi
	# fi
	#复制延迟
	if [[ ${DELAY_MON} == "Y" && $(( ${counter} % ${DELAY_PRE} )) == 0 ]]; then
		IFS=$'\n'
		if [[ ${is_recovery} =~ "f" ]]; then
			for line in `psql -t -c "select application_name,client_addr,COALESCE(trunc(extract(epoch FROM (now() - (now()- replay_lag) ))::numeric),0),trunc(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)/1024) replay_delay from pg_stat_replication;"`;do
				app_name=`echo $line|awk -F "|" '{print $1}'`
				client_addr=`echo $line|awk -F "|" '{print $2}'`
				delay_time=`echo $line|awk -F "|" '{print $3}'`
				delay_size=`echo $line|awk -F "|" '{print $4}'`
				if [[ ${delay_time} -ge ${DELAY_ALERT} ]]; then
					ms_info="Send delay to ${app_name}(${client_addr}) Delay time: ${delay_time} second wal fall behind: ${delay_size} kb."
					callsendms delay_time "${ms_info}"
				fi
			done
		else
			for line in `psql -t -c "select sender_host,pg_last_wal_replay_lsn(),received_lsn,trunc(pg_wal_lsn_diff(received_lsn,pg_last_wal_replay_lsn())/1024),trunc(extract(epoch FROM (now() - latest_end_time))::numeric) from pg_stat_wal_receiver;"`;do
				sender_host=`echo $line|awk -F "|" '{print $1}'`
				replay_lsn=`echo $line|awk -F "|" '{print $2}'`
				received_lsn=`echo $line|awk -F "|" '{print $3}'`
				delay_replay_size=`echo $line|awk -F "|" '{print $4}'`
				delay_replay_time=`echo $line|awk -F "|" '{print $5}'`
				same=$(echo ${replay_lsn} | grep "${received_lsn}")
				if [[ ! ${same} && ${delay_replay_time} -ge ${DELAY_ALERT} ]]; then
					ms_info="Replay delay from ${sender_host} delay_replay_time: ${delay_replay_time} second secdelay_replay_size: ${delay_replay_size} kb"
					callsendms delay_time "${ms_info}"
			fi
			done
		fi
		IFS=$OLD_IFS
	fi
	#长事务
	if [[ ${LONG_TRAN_MON} == "Y" && $(( ${counter} % ${LONG_TRAN_PRE} )) == 0 ]]; then
		IFS=$'\n'
		for line in `psql -t -c "SELECT pid,usename,datname,to_char(xact_start,'yyyy-mm-dd hh24:mi:ss') xact_start FROM pg_stat_activity where state <> 'idle' and (backend_xid is not null or backend_xmin is not null) and extract(epoch from (clock_timestamp()-xact_start)) > ${LONG_TRAN_ALERT}"`;do
			tpid=`echo $line|awk -F "|" '{print $1}'`
			tusename=`echo $line|awk -F "|" '{print $2}'`
			tdatname=`echo $line|awk -F "|" '{print $3}'`
			txact_start=`echo $line|awk -F "|" '{print $4}'`
			if [[ ${tpid} ]]; then
				ms_info="Long transaction:${tdatname} start at ${txact_start} pid is:${tpid}"
				callsendms long_tran "${ms_info}"
			fi
		done
		IFS=$OLD_IFS
	fi
	#账号过期
	if [[ ${USER_EXPIRED_MON} == "Y" && $(( ${counter} % ${USER_EXPIRED_PRE} )) == 0 ]]; then
		IFS=$'\n'
		for line in `psql -t -c "select usename,valuntil::date from pg_user where valuntil <> 'infinity' OR valuntil IS NULL and trunc(extract(day FROM (age(valuntil::date , now()::date)))::numeric) < ${USER_EXPIRED_ALERT};"`;do
			usename=`echo $line|awk -F "|" '{print $1}'`
			valuntil=`echo $line|awk -F "|" '{print $2}'`
			if [[ ${usename} ]]; then
				ms_info="User expire: ${usename} will expired at ${valuntil}"
				callsendms user_expire "${ms_info}"
			fi
		done
		IFS=$OLD_IFS
	fi
fi
let counter+=1
echo $counter > ${current_path}/dbcounters.tmp
echo `date '+%y-%m-%d %H:%M:%S': `"$0 executed."