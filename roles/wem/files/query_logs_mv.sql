-- otel_logs 에서 상태 테이블로 적재하는 Materialized View
CREATE MATERIALIZED VIEW IF NOT EXISTS acp_observability.mv_coordinator_query_logs_states
TO acp_observability.coordinator_query_logs_states
AS
WITH
    LogAttributes['message'] AS msg,
    LogAttributes['severity'] AS sev,
    LogAttributes['sql_state'] AS sqlstate,
    LogAttributes['detail'] AS detail_f,
    LogAttributes['hint'] AS hint_f,
    match(
        msg,
        '(?s)^(?:duration:\s*[0-9.]+\s*ms\s*)?(?:statement|execute\s+\S+):'
    ) AS is_query_line,
    (sev = 'ERROR') AS is_error_line,
    extractGroups(msg, '(?s)^duration:\s*([0-9.]+)\s*ms') AS dur_g
SELECT
    toDate(Timestamp)                      AS EventDate,
    LogAttributes['txid']                  AS TxId,
    LogAttributes['command_tag']           AS CommandTag,

    any(LogAttributes['database'])         AS Database,
    any(LogAttributes['log_user'])         AS LogUser,
    any(LogAttributes['session_id'])       AS SessionId,
    any(LogAttributes['connection_from'])  AS ConnectionFrom,
    any(LogAttributes['session_start'])    AS SessionStart,
    any(LogAttributes['cluster_identity']) AS ClusterIdentity,
    any(LogAttributes['file_name'])        AS FileName,
    any(LogAttributes['log.file.path'])    AS LogFilePath,
    any(LogAttributes['log_pid'])          AS LogPid,
    any(LogAttributes['whpg_host'])        AS WhpgHost,

    minState(Timestamp)                                              AS FirstTimestamp,
    maxState(Timestamp)                                              AS LastTimestamp,
    argMinState(msg, tuple(if(is_query_line, 0, 1), Timestamp))      AS QueryText,
    maxState(toFloat64OrZero(dur_g[1]))                              AS DurationMs,
    countState()                                                     AS LineCount,
    groupArrayIfState(msg, NOT is_query_line)                        AS RelatedMessages,
    groupUniqArrayState(sev)                                         AS Severities,

    maxState(toUInt8(is_error_line))                                 AS HasError,
    argMaxState(sqlstate, toUInt8(is_error_line))                    AS ErrorSqlState,
    argMaxState(msg, toUInt8(is_error_line))                         AS ErrorMessage,
    argMaxState(detail_f, toUInt8(is_error_line))                    AS ErrorDetail,
    argMaxState(hint_f, toUInt8(is_error_line))                      AS ErrorHint
FROM acp_observability.otel_logs
WHERE LogAttributes['log_segment'] = 'seg-1'
  AND LogAttributes['log_user'] != '__WEM_USER__'
  AND LogAttributes['txid'] != ''
  AND LogAttributes['command_tag'] != ''
GROUP BY EventDate, TxId, CommandTag;
