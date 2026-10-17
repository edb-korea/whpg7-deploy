-- 상태 테이블. __TTL_DAYS__ 는 coordinator_query_logs_ttl_days 값으로 치환된다
CREATE TABLE IF NOT EXISTS acp_observability.coordinator_query_logs_states
(
    `EventDate`         Date,
    `TxId`              String,
    `CommandTag`        String,

    `Database`          SimpleAggregateFunction(any, String),
    `LogUser`           SimpleAggregateFunction(any, String),
    `SessionId`         SimpleAggregateFunction(any, String),
    `ConnectionFrom`    SimpleAggregateFunction(any, String),
    `SessionStart`      SimpleAggregateFunction(any, String),
    `ClusterIdentity`   SimpleAggregateFunction(any, String),
    `FileName`          SimpleAggregateFunction(any, String),
    `LogFilePath`       SimpleAggregateFunction(any, String),
    `LogPid`            SimpleAggregateFunction(any, String),
    `WhpgHost`          SimpleAggregateFunction(any, String),

    `FirstTimestamp`    AggregateFunction(min, DateTime64(9)),
    `LastTimestamp`     AggregateFunction(max, DateTime64(9)),
    `QueryText`         AggregateFunction(argMin, String, Tuple(UInt8, DateTime64(9))),
    `DurationMs`        AggregateFunction(max, Float64),
    `LineCount`         AggregateFunction(count),
    `RelatedMessages`   AggregateFunction(groupArray, String),
    `Severities`        AggregateFunction(groupUniqArray, String),

    `HasError`          AggregateFunction(max, UInt8),
    `ErrorSqlState`     AggregateFunction(argMax, String, UInt8),
    `ErrorMessage`      AggregateFunction(argMax, String, UInt8),
    `ErrorDetail`       AggregateFunction(argMax, String, UInt8),
    `ErrorHint`         AggregateFunction(argMax, String, UInt8)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(EventDate)
ORDER BY (EventDate, TxId, CommandTag)
TTL EventDate + INTERVAL __TTL_DAYS__ DAY
SETTINGS index_granularity = 8192;
