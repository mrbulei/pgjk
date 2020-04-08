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
	ssh -p ${SSHPORT} $MSUSER@$MSHOST "sh ${REMODIR}/pgsendms.sh ${hostname} \"$2\" ${REMODIR}/tmp/phone#${hostname}#${PUBIP}#$1.tmp" #执行远程shell发送短信
	# echo "${REMODIR}/pgsendms.sh \"$2\" ${REMODIR}/tmp/phone#${hostname}#$1.tmp"
	ssh -p ${SSHPORT} $MSUSER@$MSHOST "rm -f ${REMODIR}/tmp/phone#${hostname}#${PUBIP}#$1.tmp"
}

###是否存活
is_alive=`pg_isready -p ${DBPORT}|grep "accepting"|wc -l `
if [[ $is_alive -eq 0 ]]; then
	ms_info="isalive: database is down"
	callsendms is_alive ms_info
else
	echo "pg is ok"
	#链接数
	if [[ ${CONN_NUM_MON} == "Y" ]]; then
		conn_num=`psql -t -q -c "select count(*) from pg_stat_activity;"`
		if [[ ${conn_num} -ge ${CONN_NUM_ALERT} ]]; then
			ms_info="Number of connections: ${conn_num}"
			callsendms conn_num "${ms_info}"
		fi
		echo ${conn_num}
	fi
	#等待事件
	if [[ ${WAIT_NUM_MON} == "Y" ]]; then
		IFS=$'\n'
		for line in `psql -t -c "select wait_event,count(*) from pg_stat_activity where wait_event is not null and wait_event not in ('ClientRead') group by wait_event;"`; do
			wait_name=`echo $line|awk -F "|" '{print $1}'`
			wait_count=`echo $line|awk -F "|" '{print $2}'`
			if [[ ${wait_count} -ge ${WAIT_NUM_ALERT} ]]; then
				ms_info="Wait event: ${wait_name} ${wait_count}"
				callsendms wait_num "${ms_info}"
			fi
			echo ${wait_name} ${wait_count} 
		done
		IFS=$OLD_IFS
	fi
	#备库查看事务延迟
	if [ ${IS_MASTER} == "N" -a ${DELAY_MON} == "Y" ]; then
		delay_time=`psql -t -c "select trunc(extract(epoch from now() - pg_last_xact_replay_timestamp()));"`
		if [[ ${delay_time} -ge ${DELAY_ALERT} ]]; then
			ms_info="Delay time: ${delay_time} (second)"
			callsendms delay_time "${ms_info}"
		fi
		echo ${delay_time}
	fi
fi

echo `date '+%y-%m-%d %H:%M:%S': `"$0 executed."