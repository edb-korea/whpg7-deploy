# WarehousePG Ansible 배포 프로젝트

RHEL 기반 환경에 **WarehousePG 7.x** 클러스터를 완전 자동화 배포하는 Ansible 프로젝트입니다.

## 전체 파일 구조

```
whpg-ansible/
├── ansible.cfg                        # Ansible 설정 (인벤토리, SSH, 로그 등)
├── inventory/
│   └── hosts                          # 클러스터 노드 인벤토리
├── group_vars/
│   ├── whpg_cluster.yml               # 공통 변수 (버전, 경로, 플래그 등)
│   └── vault.yml                      # 민감 변수 (ansible-vault로 암호화)
├── playbooks/
│   ├── site.yml                       # 전체 배포 (모든 Phase 순차 실행)
│   ├── 01_os_preconfig.yml            # Phase 1: OS 사전 구성
│   ├── 02_whpg_install.yml            # Phase 2: RPM 설치 + SSH 키 교환
│   ├── 03_whpg_init.yml               # Phase 3: 클러스터 초기화
│   ├── 04_extensions.yml              # Phase 4: Extension 설치
│   ├── 05_wem.yml                     # Phase 5: WEM (모니터링)
│   ├── 06_pgbouncer.yml               # Phase 6: pgBouncer
│   ├── 07_coordinator_ha.yml          # Phase 7: Coordinator HA
│   └── ops/
│       ├── status.yml                 # 클러스터 상태 확인
│       ├── start.yml                  # 클러스터 시작
│       ├── stop.yml                   # 클러스터 정지
│       ├── recover_segments.yml       # 세그먼트 복구 (gprecoverseg)
│       ├── resync_standby.yml         # Standby 재동기화 (장애 후 재구성)
│       └── minor_upgrade.yml          # 마이너 업그레이드
└── roles/
    ├── os_preconfig/                  # OS 사전 구성
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── chrony.conf.j2         # NTP 설정
    │       ├── tuned.conf.j2          # THP 비활성화 / Read-ahead
    │       └── whpg-local.repo.j2     # 내부 YUM 레포
    ├── whpg_install/                  # RPM 설치 + gpssh-exkeys
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   └── templates/hostfile_all.j2
    ├── whpg_init/                     # 클러스터 초기화
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── gpinitsystem_config.j2
    │       └── seg_hosts.j2
    ├── whpg_extensions/               # Extension 설치 (기본 + 선택)
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   └── templates/pxf-core-site.xml.j2
    ├── wem/                           # WEM (Prometheus + Loki + Grafana + Collector)
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── prometheus.yml.j2
    │       ├── prometheus.service.j2
    │       ├── loki-config.yml.j2
    │       ├── loki.service.j2
    │       ├── grafana.ini.j2
    │       ├── grafana-datasource-prometheus.yml.j2
    │       ├── grafana-datasource-loki.yml.j2
    │       ├── postgres_exporter.service.j2
    │       ├── promtail-config.yml.j2
    │       └── promtail.service.j2
    ├── pgbouncer/                     # pgBouncer (Coordinator)
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── pgbouncer.ini.j2
    │       └── pgbouncer.service.j2
    └── coordinator_ha/                # keepalived VIP 기반 HA
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/main.yml
        └── templates/
            ├── keepalived-master.conf.j2
            ├── keepalived-backup.conf.j2
            ├── whpg_healthcheck.sh.j2
            ├── whpg_promote.sh.j2
            └── whpg_demote.sh.j2
```

---

## 사전 준비

### 1. 인벤토리 수정 (`inventory/hosts`)

```ini
[coordinator]
cdw ansible_host=192.168.10.10

[standby_coordinator]
scdw ansible_host=192.168.10.11

[segments]
sdw1 ansible_host=192.168.10.21
sdw2 ansible_host=192.168.10.22
sdw3 ansible_host=192.168.10.23
sdw4 ansible_host=192.168.10.24
```

### 2. 핵심 변수 설정 (`group_vars/whpg_cluster.yml`)

반드시 환경에 맞게 수정해야 할 항목:

| 변수 | 설명 | 예시 |
|------|------|------|
| `whpg_version` | 설치할 WHPG 버전 | `7.4.0` |
| `whpg_rpm_local_path` | 로컬 RPM 경로 | `/tmp/warehousepg-db-7.4.0-rhel8-x86_64.rpm` |
| `coordinator_vip` | HA용 Virtual IP | `192.168.10.100` |
| `xfs_data_device` | 데이터 디스크 | `/dev/sdb` |
| `pxf_namenode_host` | Hadoop NameNode | `namenode.internal` |
| `whpg_local_repo_baseurl` | 내부 YUM 레포 URL | `http://repo.internal/whpg` |
| `segment_hosts` | 세그먼트 호스트 목록 | `[sdw1, sdw2, ...]` |

### 3. 민감 변수 암호화 (`group_vars/vault.yml`)

```bash
# vault.yml 편집 후 암호화
ansible-vault encrypt group_vars/vault.yml

# 실행 시 vault 비밀번호 입력
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### 4. WHPG RPM 파일 준비

EDB 계정에서 RPM 다운로드 후 control node에 배치:
```bash
ls /tmp/warehousepg-db-7.4.0-rhel8-x86_64.rpm
```

---

## 실행 방법

### 전체 배포 (모든 Phase)

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### 단계별 실행

```bash
# Phase 1: OS 사전 구성
ansible-playbook playbooks/01_os_preconfig.yml

# ★ SELinux/cgroup 변경 후 전체 노드 reboot 필요
# ssh 각 노드에서: reboot

# Phase 2: WHPG RPM 설치 + gpssh-exkeys
ansible-playbook playbooks/02_whpg_install.yml

# Phase 3: 클러스터 초기화 (cluster → mirror → standby 순서)
ansible-playbook playbooks/03_whpg_init.yml

# Phase 4: Extension 설치 (PXF, pgaudit, madlib, plr, pgvector 등)
ansible-playbook playbooks/04_extensions.yml

# Phase 5: WEM (Prometheus + Loki + Grafana + postgres_exporter + promtail)
ansible-playbook playbooks/05_wem.yml

# Phase 6: pgBouncer
ansible-playbook playbooks/06_pgbouncer.yml

# Phase 7: Coordinator HA (keepalived VIP)
ansible-playbook playbooks/07_coordinator_ha.yml
```

### 태그를 활용한 선택 실행

```bash
# Phase 1+2만 실행
ansible-playbook playbooks/site.yml --tags "phase1,phase2"

# Extension만 재설치
ansible-playbook playbooks/site.yml --tags "extensions"

# WEM + pgBouncer만
ansible-playbook playbooks/site.yml --tags "wem,pgbouncer"
```

### Dry-run (변경 없이 검증)

```bash
ansible-playbook playbooks/site.yml --check --diff
```

---

## OS 사전 구성 항목 상세 (Phase 1)

| 항목 | 파일 | 내용 |
|------|------|------|
| SELinux 비활성화 | `/etc/selinux/config` | `SELINUX=disabled` |
| firewalld 비활성화 | systemd | stopped + disabled |
| OS 커널 파라미터 | `/etc/sysctl.d/95-whpg.conf` | shm, vm, net 튜닝 27개 |
| /etc/hosts | `/etc/hosts` | 클러스터 전체 호스트 자동 등록 |
| cgroup v1 강제 사용 | `/etc/default/grub` | `systemd.unified_cgroup_hierarchy=0` |
| gpadmin 사용자/그룹 | `/etc/passwd` | uid/gid=5000, .bashrc 환경변수 |
| SSH 무암호 로그인 | `~/.ssh/authorized_keys` | gpadmin RSA 키 전체 노드 배포 |
| ulimits | `/etc/security/limits.d/95-gpadmin.conf` | nofile=524288, nproc=131072 |
| 로컬 YUM 레포 | `/etc/yum.repos.d/whpg-local.repo` | 내부 레포 설정 |
| XFS 마운트 옵션 | `/etc/fstab` | noatime, allocsize=16m 등 |
| I/O 스케쥴러 | `/etc/udev/rules.d/99-vmware-db-scheduler.rules` | `none` (SSD/VMware) |
| THP 비활성화 | `/etc/tuned/whpg-optimized/tuned.conf` | `transparent_hugepages=never` |
| Read-ahead 조정 | tuned profile | `readahead=16` |
| SSH 임계값 | `/etc/ssh/sshd_config` | MaxStartups=100:30:200, MaxSessions=200 |
| NTP | `/etc/chrony.conf` | chrony 서버 설정 + 서비스 활성화 |
| 필수 패키지 | yum | rsync, sysstat, java-11, perl 등 |

---

## Extension 설치 현황

### 기본 Extension (항상 설치 - `install_*: true`)

| Extension | 패키지명 | 설명 |
|-----------|----------|------|
| PXF | `warehousepg-pxf` | Hadoop/HDFS 외부 테이블 |
| pgaudit | `warehousepg-pgaudit` | 감사 로그 |
| user_profile | `warehousepg-user-profile` | 사용자 프로파일 관리 |
| anonymizer | `warehousepg-anonymizer` | 데이터 익명화 |
| whpg_fdw | 내장 | 외부 데이터 래퍼 |
| diskquota | `warehousepg-diskquota` | 디스크 할당량 |
| Data Science (Python) | `warehousepg-python3-datascience` | numpy, pandas, scipy 등 |
| MADlib | `warehousepg-madlib` | 머신러닝 라이브러리 |
| PLR | `warehousepg-plr` | R 프로시저 언어 |
| PL/Java | `warehousepg-pljava` | Java 프로시저 언어 |

### Optional Extension (group_vars에서 `true`로 활성화)

| 변수 | Extension | 설명 |
|------|-----------|------|
| `install_postgis` | PostGIS | 지리정보 시스템 |
| `install_hll` | HyperLogLog | 근사 집계 |
| `install_q3c` | q3c | 구면 천체 인덱스 |
| `install_pgsphere` | pgSphere | 구면 기하 |
| `install_pgfs` | pgfs | 파일시스템 접근 |
| `install_pgaa` | pgaa | 고급 감사 |
| `install_pgvector` | pgvector | 벡터 유사도 검색 |
| `install_vectorchord` | VectorChord | 고성능 벡터 검색 |
| `install_flowserver` | flowserver | 워크플로우 서버 |

---

## WEM 구성 (Phase 5)

```
[모든 노드]
  └─ promtail → Loki (로그)
  └─ node_exporter (포트 9100) → Prometheus (시스템 메트릭)

[Coordinator (cdw)]
  └─ postgres_exporter (포트 9187) → Prometheus (DB 메트릭)

[Standby Coordinator (scdw)]
  ├─ Prometheus  (포트 9090) ← 메트릭 수집
  ├─ Loki        (포트 3100) ← 로그 수집
  └─ Grafana     (포트 3000) ← WEM Dashboard
       ├─ Datasource: Prometheus (자동 등록)
       └─ Datasource: Loki      (자동 등록)
```

Grafana 초기 접속: `http://scdw:3000` (admin / admin)

---

## Coordinator HA 구성 (Phase 7)

keepalived를 통한 VIP 기반 Active/Standby 구성:

```
[cdw  - MASTER, priority=110] ─┐
                                ├── VIP: coordinator_vip (예: 192.168.10.100:5432)
[scdw - BACKUP, priority=90 ] ─┘
```

**장애 절체 흐름:**
1. keepalived 헬스체크 (`psql -c "SELECT 1"`) 실패 감지
2. scdw가 VIP를 인수 (BACKUP → MASTER)
3. `gpinitstandby -n` 실행으로 standby → active coordinator 승격
4. 애플리케이션은 VIP로 연결하므로 투명하게 절체

**복구 후 재동기화:**
```bash
ansible-playbook playbooks/ops/resync_standby.yml
```

---

## 운영 플레이북

```bash
# 클러스터 상태 확인 (gpstate + pgBouncer + Standby 동기화)
ansible-playbook playbooks/ops/status.yml

# 클러스터 시작 / 정지
ansible-playbook playbooks/ops/start.yml
ansible-playbook playbooks/ops/stop.yml

# 세그먼트 복구 (gprecoverseg → rebalance)
ansible-playbook playbooks/ops/recover_segments.yml

# Standby 재동기화 (장애 후 원상복구)
ansible-playbook playbooks/ops/resync_standby.yml

# 마이너 업그레이드
ansible-playbook playbooks/ops/minor_upgrade.yml \
  -e "new_rpm=/path/to/warehousepg-db-7.4.1-rhel8-x86_64.rpm"
```

---

## 주의사항

1. **SELinux / cgroup 변경 후 리부팅 필수**: Phase 1 완료 후 전체 노드 reboot
2. **RPM 파일**: EDB 라이선스 계정에서 직접 다운로드 필요
3. **gpinitsystem 멱등성**: DB가 이미 초기화된 경우 Phase 3는 skip (`already exists` 처리됨)
4. **XFS 디스크**: `xfs_data_device`가 비어있으면 XFS 포맷/마운트 단계를 건너뜀
5. **PXF Hadoop**: `pxf_hadoop_enabled: true`이고 `pxf_namenode_host` 설정 시 core-site.xml 자동 배포
6. **RPM 패키지명**: 배포 환경에 따라 `warehousepg-*` 패키지명이 다를 수 있으므로 확인 후 수정

---

## 참고 문서

- [WarehousePG 설치 가이드](https://www.enterprisedb.com/docs/warehousepg/latest/install_guide/)
- [EDB 공식 Ansible 예제](https://www.enterprisedb.com/docs/warehousepg/latest/install_guide/ansible-example/)
- [WHPG 설치 가이드 (한국어 Tips)](https://github.com/unixfree/WarehousePG-Tip/blob/main/02.설치가이드.md)
- [Coordinator HA v2](https://github.com/unixfree/whpg_coordinator_ha_v2)
- [WEM 설치 가이드](https://www.enterprisedb.com/docs/supported-open-source/warehousepg/wem/installing/)
