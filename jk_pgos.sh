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
if [[ ! -f oscounters.tmp ]]; then
	echo 0 > ${current_path}/oscounters.tmp
	counter=0
else
	counter=`cat ${current_path}/oscounters.tmp`
	#statements
fi

###cpu
if [[ ${CPU_MON} == "Y" && $(( ${counter} % ${CPU_PER} )) == 0 ]];then
	cpu_usage=`vmstat 1 5 |sed -n '3,7p'|awk '{sum+=$15}END{print 100-sum/NR}'`
	# wait
	if [ `echo "${cpu_usage} >= ${CPU_ALERT}"|bc` -eq 1 ];then
		ms_info="Cpu usage: ${cpu_usage}%"
		callsendms cpu_usage "${ms_info}"
	fi
fi

###mem
if [[ ${MEM_MON} == "Y" && $(( ${counter} % ${MEM_PER} )) == 0 ]];then
	mem_usage=`free |grep Mem |awk '{print ($2-$7)/($2)*100}'`
	if [ `echo "${mem_usage} >= ${MEM_ALERT}"|bc` -eq 1 ];then
		ms_info="Memory usage: ${mem_usage}%"
		callsendms mem_usage "${ms_info}"
	fi
fi

##file system

if [[ ${FS_USAGE_MON} == "Y" && $(( ${counter} % ${FS_USAGE_PER} )) == 0 ]];then
	IFS=$'\n'
	for line in `df -hT|sed -n '2,$p'|grep -v "tmpfs"` ;do
		# fs_usage=`echo $line |awk '{if($2!="tmpfs")print $6}'|awk -F '%' '{print $1}'`
		fs_usage=`echo $line |awk '{print $6}'|awk -F '%' '{print $1}'`
		fs_name=`echo $line |awk '{print $7}'`
		fs_free=`echo $line |awk '{print $5}'`
		if [ ${fs_usage} -ge ${FS_USAGE_ALERT} ];then
			ms_info="File system usage: ${fs_name} usage: ${fs_usage}% free: ${fs_free}"
			callsendms fs_usage "${ms_info}"
		fi
	done
	IFS=$OLD_IFS
fi
let counter+=1
echo $counter > ${current_path}/oscounters.tmp
echo `date '+%y-%m-%d %H:%M:%S': `"$0 executed."