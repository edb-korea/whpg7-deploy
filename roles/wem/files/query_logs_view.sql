-- 최종 조회용 View
CREATE VIEW IF NOT EXISTS acp_observability.coordinator_query_logs AS
SELECT
    TxId,
    CommandTag,
    any(Database)                         AS Database,
    any(LogUser)                          AS LogUser,
    any(SessionId)                        AS SessionId,
    any(ConnectionFrom)                   AS ConnectionFrom,
    any(SessionStart)                     AS SessionStart,
    any(ClusterIdentity)                  AS ClusterIdentity,
    any(FileName)                         AS FileName,
    any(LogFilePath)                      AS LogFilePath,
    any(LogPid)                           AS LogPid,
    any(WhpgHost)                         AS WhpgHost,

    minMerge(FirstTimestamp)              AS FirstTimestamp,
    maxMerge(LastTimestamp)                AS LastTimestamp,
    argMinMerge(QueryText)                 AS QueryText,
    nullIf(maxMerge(DurationMs), 0)         AS DurationMs,
    countMerge(LineCount)                   AS LineCount,
    groupArrayMerge(RelatedMessages)        AS RelatedMessages,
    groupUniqArrayMerge(Severities)         AS Severities,

    maxMerge(HasError)                      AS HasError,
    argMaxMerge(ErrorSqlState)               AS ErrorSqlState,
    argMaxMerge(ErrorMessage)                AS ErrorMessage,
    argMaxMerge(ErrorDetail)                 AS ErrorDetail,
    argMaxMerge(ErrorHint)                   AS ErrorHint
FROM acp_observability.coordinator_query_logs_states
GROUP BY TxId, CommandTag;
