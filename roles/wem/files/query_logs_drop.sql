-- 기존 Coordinator Query Logs 객체 삭제 (coordinator_query_logs_recreate=true 일 때만 실행)
DROP VIEW IF EXISTS acp_observability.coordinator_query_logs;
DROP VIEW IF EXISTS acp_observability.mv_coordinator_query_logs_states;
DROP TABLE IF EXISTS acp_observability.coordinator_query_logs_states;
