#!/bin/bash
if [ $# -ne 1 ];then
   echo "Please provide alter sql as a parameter!"
   exit;
fi

log=/tmp/alter_`date +"%Y%m%d_%H_%M_%S"`.log
mysql_user=root
mysql_password=root
alter_sql="$1"
interval=3

function turnon_mdl_instrument(){
  mysql -u$mysql_user -p$mysql_password -NBe "UPDATE performance_schema.setup_instruments SET ENABLED = 'YES' WHERE NAME = 'wait/lock/metadata/sql/mdl'" 2> /dev/null
}

function turnon_stage_tracking(){
  mysql -u$mysql_user -p$mysql_password -NBe "UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', TIMED = 'YES' WHERE NAME = 'stage/sql/altering table'" 2> /dev/null

}

function turnoff_stage_tracking(){
  mysql -u$mysql_user -p$mysql_password -NBe "UPDATE performance_schema.setup_instruments SET ENABLED = 'NO', TIMED = 'NO' WHERE NAME = 'stage/sql/altering table'"  2>/dev/null

}

function run_alter_sql(){
  echo "[`date +"%Y-%m-%d %H:%M:%S"`] SQL: $alter_sql started running !" | tee -a $log
  nohup mysql -u$mysql_user -p$mysql_password -NBe "$alter_sql" 2>/tmp/alter.err &
  sleep 1

}
turnon_mdl_instrument
turnon_stage_tracking
run_alter_sql


while :
do
  cc=`mysql -u$mysql_user -p$mysql_password -NBe "select count(*) from information_schema.processlist where State='Waiting for table metadata lock' " 2> /dev/null`
  if [ $cc -gt 0 ];then
     echo "Waiting for table metadata lock... [$cc] sleep 1" | tee -a $log
     mysql -u$mysql_user -p$mysql_password -e "select OBJECT_TYPE,OBJECT_SCHEMA,OBJECT_NAME,LOCK_TYPE,LOCK_DURATION,LOCK_STATUS,OWNER_THREAD_ID,PROCESSLIST_ID  from performance_schema.metadata_locks m left join performance_schema.threads t on m.owner_thread_id=t.thread_id  where OBJECT_SCHEMA <> 'performance_schema'" 2>/dev/null
     
     sleep 1
  else
     echo "[`date +"%Y-%m-%d %H:%M:%S"`] Get MDL Lock! " | tee -a $log
     echo "[`date +"%Y-%m-%d %H:%M:%S"`] Begin to run SQL($alter_sql)..." | tee -a $log
     start=`date +%s`
     break;
  fi

done

while :
do
 
 c=`mysql -u$mysql_user -p$mysql_password -NBe " SELECT count(*) FROM performance_schema.events_stages_current" 2> /dev/null`
 if [ $c -eq 0 ];then
   end=`date +%s`
   echo "[`date +"%Y-%m-%d %H:%M:%S"`] SQL: $alter_sql running finished!" | tee -a $log
   time_used=$[end-start]
   echo "Time used:${time_used}s" | tee -a $log
   break;
 fi

 mysql -u$mysql_user -p$mysql_password -e " SELECT EVENT_NAME, WORK_COMPLETED, WORK_ESTIMATED,(WORK_COMPLETED/WORK_ESTIMATED)*100 as COMPLETED FROM performance_schema.events_stages_current" 2>/dev/null
 sleep $interval

done

turnoff_stage_tracking

echo "-----------error log--------"
cat /tmp/alter.err
