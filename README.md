# pgjk
jk_pgdb.sh 数据库采集
jk_pgos.sh 系统采集
pgmonitor.conf 配置

定时任务

*/5 * * * * /home/postgres/xj_monitor/jk_pgdb.sh > jk_pgdb.out 2>&1
*/5 * * * * /home/postgres/xj_monitor/jk_pgos.sh > jk_pgos.out 2>&1