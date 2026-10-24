# WarehousePG Ansible 배포 프로젝트

RHEL 기반 환경에 **WarehousePG 7.x** 클러스터를 완전 자동화 배포하는 Ansible 프로젝트입니다.

## 전체 파일 구조

```
whpg-ansible/
├── ansible.cfg                        # Ansible 설정 (인벤토리, SSH, 로그 등)
├── inventory/
│   ├── hosts                          # 클러스터 노드 인벤토리
│   ├── whpg_cluster.yml               # 공통 변수 (버전, 경로, 포트, 플래그 등) ← 여기서 편집
│   ├── vault.yml                      # 민감 변수 (ansible-vault로 암호화) ← 여기서 편집
│   └── group_vars/
│       └── whpg_cluster/
│           ├── main.yml -> ../../whpg_cluster.yml   # 심볼릭 링크 (Ansible 로드용)
│           └── vault.yml -> ../../vault.yml         # 심볼릭 링크 (Ansible 로드용)
├── playbooks/
│   ├── site.yml                       # 전체 배포 (모든 Phase 순차 실행)
│   ├── 01_os_preconfig.yml            # Phase 1: OS 사전 구성
│   ├── 02_whpg_install.yml            # Phase 2: RPM 설치 + SSH 키 교환
│   ├── 03_whpg_init.yml               # Phase 3: 클러스터 초기화
│   ├── 04_extensions.yml              # Phase 4: Extension 설치
│   ├── 05_pgbouncer.yml               # Phase 5: pgBouncer
│   ├── 06_coordinator_ha.yml          # Phase 6: Coordinator HA
│   ├── 07_wem.yml                     # Phase 7: WEM 1.4 (ClickHouse + Host Agent + otelcol, VIP 사용)
│   ├── 08_diskquota.yml               # Phase 8: cluster 차원 diskquota (post 작업, soft 90% / hard 92%)
│   └── ops/
│       ├── status.yml                 # 클러스터 상태 확인
│       ├── start.yml                  # 클러스터 시작
│       ├── stop.yml                   # 클러스터 정지
│       ├── recover_segments.yml       # 세그먼트 복구 (gprecoverseg)
│       ├── resync_standby.yml         # Standby 재동기화 (장애 후 재구성)
│       ├── remove_wem.yml             # WEM 1.4 이상 삭제
│       ├── expand_segments.yml        # Segment 4대 단위 증설 (gpexpand)
│       └── minor_upgrade.yml          # 마이너 업그레이드 (RPM 파일 지정, 이전 방식)
│   └── upgrade/
│       └── upgrade.yml                # core / pxf / backup / flowserver / extension 업그레이드 (-e upgrade=...)
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
    ├── whpg_expand/                   # Segment 증설 (plan / prepare / gpexpand)
    ├── wem/                           # WEM 1.4 (edb-korea/wem-deploy 기반)
    │   ├── defaults/main.yml          # WEM 변수 전체
    │   ├── tasks/                     # 00-checks ~ 10-summary, upgrade, remove-wem14 (단계별, tag)
    │   └── templates/
    │       ├── wem.conf.j2                # WEM 설정
    │       └── otelcol_config_local.yaml.j2   # otelcol override (config_local.yaml)
    ├── pgbouncer/                     # pgBouncer (Coordinator)
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── pgbouncer.ini.j2
    │       └── pgbouncer.service.j2
    ├── whpg_diskquota/                # cluster diskquota (preload, CREATE EXTENSION, set_cluster_quota, hard limit 자동 전환)
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   └── templates/whpg_diskquota_check.sh.j2
    ├── whpg_upgrade/                  # 패키지를 repo 최신 버전으로 업그레이드 (minor upgrade 문서 절차)
    │   ├── defaults/main.yml
    │   └── tasks/main.yml
    └── coordinator_ha/                # keepalived VIP 기반 HA
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/main.yml
        └── templates/
            ├── keepalived.conf.j2     # MASTER/BACKUP 공용 (그룹 기준 자동 결정)
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

### 2. 핵심 변수 설정 (`inventory/whpg_cluster.yml`)

> Ansible 은 `inventory/group_vars/` 아래만 자동 로드하므로, 그 안에 `inventory/whpg_cluster.yml`, `inventory/vault.yml` 을
> 가리키는 심볼릭 링크를 두었습니다. 편집은 `inventory/` 바로 아래 파일에서 하면 되고, 링크는 삭제하지 마세요.

호스트 정보(`coordinator_host`, `standby_coordinator_host`, `segment_hosts`, `wem_host`)는
inventory 그룹에서 자동으로 도출되므로 **inventory/hosts 만 수정**하면 됩니다.

반드시 환경에 맞게 수정해야 할 항목:

| 변수 | 설명 | 예시 |
|------|------|------|
| `whpg_version` | 설치할 WHPG 버전 | `7.5.0` |
| `local_rpm_dir` | Controller 의 RPM 저장 경로 | `/opt/whpg-rpms` |
| `coordinator_vip` / `coordinator_vip_interface` | HA용 Virtual IP / NIC | `192.168.10.100` / `eth0` |
| `whpg_data_mounts` | 데이터 루트 경로와 디스크 (1개 `/data` 또는 2개 `/data1`, `/data2`, `device` 비우면 기존 FS 사용) | `{path: /data, device: ""}` / `{path: /data1, device: /dev/sdb}` |
| `pxf_namenode_host` | Hadoop NameNode | `namenode.internal` |
| `whpg_local_repo_baseurl` | 내부 YUM 레포 URL | `http://repo.internal/whpg` |

자주 조정하는 항목:

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `whpg_coordinator_port` | Coordinator 포트 (psql/pgBouncer/HA/WEM 공통) | `5432` |
| `whpg_port_base` / `whpg_mirror_port_base` | Primary / Mirror 시작 포트 | `6000` / `7000` |
| `whpg_database` | 관리용 DB 이름 | `gpadmin` |
| `whpg_data_root` | Coordinator/Standby 데이터 루트 | `whpg_data_mounts` 첫 번째 path |
| `whpg_segments_per_host` | 호스트당 primary segment 수 (데이터 디스크 수의 배수) | `2` (4, 8 …) |
| `primary_data_dirs` / `mirror_data_dirs` | 세그먼트 상위 디렉토리 (`whpg_data_mounts`, `whpg_segments_per_host` 에서 자동 생성) | 1개: `/data/primary` / 2개: `/data1/primary`, `/data2/primary` (mirror 동일) |
| `whpg_pg_hba_rules` | pg_hba.conf 추가 규칙 | gpadmin md5 등 |
| `install_*` | Extension 설치 플래그 | 아래 표 참고 |

Role 내부 튜닝값(sysctl, ulimit, gpconfig 파라미터, pgBouncer/keepalived 세부 설정 등)은
`roles/<role>/defaults/main.yml` 에 있으며, 필요한 값만 group_vars 에 같은 이름으로 정의하면 override 됩니다.

```yaml
# 예) sysctl 일부만 변경/추가
os_sysctl_params_extra:
  vm.swappiness: "1"

# 예) gpconfig 파라미터 추가
whpg_gpconfig_params_extra:
  - { name: gp_vmem_protect_limit, value: "8192" }
```

### 3. 민감 변수 암호화 (`inventory/vault.yml`)

```bash
# vault.yml 편집 후 암호화
ansible-vault encrypt inventory/vault.yml

# 실행 시 vault 비밀번호 입력
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### 4. WHPG RPM 파일 준비

EDB 계정에서 RPM 다운로드 후 control node 의 `local_rpm_dir` 에 배치 (없으면 dnf fallback):
```bash
ls /opt/whpg-rpms/warehouse-pg-7-7.5.0_WHPG-1.el9.x86_64.rpm
```

RPM 선택 규칙 (`roles/rpm_install/tasks/select.yml`):
- 파일명이 아니라 RPM 내부 패키지명이 정확히 일치하는 파일만 대상
  (`whpg-backup` ↔ `whpg-backup-ddboost-plugin`, `warehouse-pg-7` ↔ `warehouse-pg-7-clients` 구분)
- 같은 패키지가 여러 버전이면 버전 비교로 최신 선택 (`1.9.1` < `1.11.0`)
- Core 는 `whpg_version` 과 버전이 일치하는 RPM 만 사용 (여러 버전이 같이 있어도 됨)

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

# Phase 3: 클러스터 초기화 (primary → mirror 4대 단위 spread → standby 순서)
ansible-playbook playbooks/03_whpg_init.yml

# Phase 4: Extension 설치 (PXF, pgaudit, madlib, plr, pgvector 등)
ansible-playbook playbooks/04_extensions.yml

# Phase 5: pgBouncer
ansible-playbook playbooks/05_pgbouncer.yml

# Phase 6: Coordinator HA (keepalived VIP)
ansible-playbook playbooks/06_coordinator_ha.yml

# Phase 7: WEM 1.4 (ClickHouse + Host Agent + otelcol) - HA 의 VIP 를 사용하므로 HA 이후
ansible-playbook playbooks/07_wem.yml

# Phase 8: cluster 차원 diskquota (post 작업, preload 추가 시 재시작)
ansible-playbook playbooks/08_diskquota.yml
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
| /etc/hosts | `/etc/hosts` | 클러스터 전체 호스트 자동 등록 (`IP 실제hostname alias`, alias: cdw / scdw / sdw1… , `host_alias` 로 변경) |
| cgroup v1 강제 사용 | `/etc/default/grub` | `systemd.unified_cgroup_hierarchy=0` |
| gpadmin 사용자/그룹 | `/etc/passwd` | 이미 있으면 기존 uid/gid 유지, 없으면 `gpadmin_uid` / `gpadmin_gid`(5000)로 생성, .bashrc 환경변수 |
| SSH 무암호 로그인 | `~/.ssh/authorized_keys`, `known_hosts` | gpadmin RSA 키 전체 노드 배포, 클러스터 호스트 키 등록(ssh-keyscan, gpssh-exkeys 용), `StrictHostKeyChecking accept-new` |
| ulimits | `/etc/security/limits.d/95-gpadmin.conf` | nofile=524288, nproc=131072 |
| 로컬 YUM 레포 | `/etc/yum.repos.d/whpg-local.repo` | 내부 레포 설정 |
| XFS 마운트 옵션 | `/etc/fstab` | noatime, allocsize=16m 등 (quota 사용 시 prjquota) |
| 데이터 볼륨 quota | `/etc/projects`, `/etc/projid`, xfs_quota | 데이터 경로가 있는 볼륨에 XFS project quota hard = 볼륨 크기 × `whpg_data_quota_percent`(기본 95%) |
| I/O 스케쥴러 | `/etc/udev/rules.d/99-vmware-db-scheduler.rules` | `none` (SSD/VMware) |
| 시스템 python3 | alternatives | `/usr/bin/python3` 를 OS 기본(RHEL 9: 3.9)으로 유지 (tuned 등 RHEL 도구용). WHPG 는 `greenplum_path.sh` 가 PATH 앞에 넣는 `$GPHOME/ext/python3.11/bin` 으로 python3.11 사용 (`os_fix_system_python3`) |
| THP 비활성화 | `/etc/tuned/whpg-optimized/tuned.conf` | `transparent_hugepages=never` |
| Read-ahead 조정 | tuned profile | `readahead=16` |
| SSH 임계값 | `/etc/ssh/sshd_config` | MaxStartups=100:30:200, MaxSessions=200 |
| NTP | `/etc/chrony.conf` | chrony 서버 설정 + 서비스 활성화 |
| 필수 패키지 | yum | rsync, sysstat, java-11, perl 등 |

### 데이터 볼륨 quota (`roles/os_preconfig/tasks/data_quota.yml`)

`whpg_data_mounts` 의 각 경로가 올라가 있는 **볼륨(파일시스템)** 에 XFS project quota 를 겁니다 (같은 볼륨은 한 번).

| 데이터 경로 | quota 대상 | quota 가 꺼져 있을 때 |
|---|---|---|
| `/data` (/ 아래 디렉토리) | `/` 볼륨 전체 | 커널 인자 `rootflags` 에 `prjquota` 추가 → **재부팅 후 다시 실행**하면 한도 적용 |
| `/data1`, `/data2` (별도 마운트) | 각 마운트 | fstab 에 `prjquota` 추가 후 umount → mount (사용 중이면 중단) |

- 한도: hard = 볼륨 크기 × `whpg_data_quota_percent`(95), soft = `whpg_data_quota_soft_percent`(0 = 없음). 값이 다를 때만 다시 설정합니다.
- `/etc/projects` 에 이미 있는 볼륨은 그 project 를 그대로 쓰고, 없으면 `whpg_data_quota_project_prefix` + 경로 이름(`whpgroot`, `whpgdata1` …)으로
  `whpg_data_quota_project_id_base`(1001)부터 할당합니다. 처음 등록할 때 `xfs_quota project -s` 로 볼륨의 기존 파일에 project 를 붙입니다.
- XFS 가 아닌 볼륨은 경고만 하고 건너뜁니다. 끄려면 `whpg_data_quota_enabled: false`.
- 확인: `xfs_quota -x -c 'report -p -h' /` (또는 `/data1`)

---

## Extension 설치 현황

### 기본 Extension (`install_*: true`)

패키지명, CREATE EXTENSION 이름, shared_preload_libraries 여부는
`inventory/whpg_cluster.yml` 의 `whpg_extension_catalog` 한 곳에서 관리하며 설치/업그레이드 playbook 이 함께 사용합니다.

| 변수 | 패키지명 | CREATE EXTENSION / preload | 설명 |
|------|----------|----------------------------|------|
| `install_pxf` | `edb-whpg7-pxf` | - | Hadoop/HDFS 외부 테이블 |
| `install_pgaudit` | `edb-whpg7-pgaudit` | `pgaudit` / preload | 감사 로그 |
| `install_user_profile` | `edb-whpg7-user_profile` | preload | 사용자 프로파일 관리 |
| `install_anonymizer` | `edb-whpg7-anonymizer` | `anon` | 데이터 익명화 |
| `install_whpg_fdw` | `edb-whpg7-whpg_fdw` | `whpg_fdw` | 외부 데이터 래퍼 |
| `install_diskquota` | `edb-whpg7-diskquota` | preload `diskquota-<diskquota_lib_version>` | 디스크 할당량 |
| `install_datascience_python` | `edb-whpg7-data-science-python311` | - | Python 3.11 numpy, pandas, scipy 등 |
| `install_datascience_r` | `edb-whpg7-data-science-r` | - | R 4.5.1 Data Science 패키지 (PLR 필요) |
| `install_madlib` | `edb-whpg7-madlib` | madpack | 머신러닝 라이브러리 |
| `install_plr` | `edb-whpg7-plr` | `plr` | R 프로시저 언어 |
| `install_pljava` | `edb-whpg7-pljava` | `pljava` | Java 프로시저 언어 |
| `install_pg_partman` | `edb-whpg7-pg_partman` | `pg_partman` | 파티션 관리 |
| `install_whpg_copy` | `edb-whpg-copy` | - | WHPG 인스턴스 간 데이터 복사 CLI |
| `install_whpg_cron` | `edb-whpg7-whpg-cron` | `pg_cron` / preload | 작업 스케줄러 (`cron.database_name` = `whpg_database`) |
| `install_whpg_backup` | `whpg-backup` | - | 백업 도구 |

> diskquota 는 버전이 붙은 라이브러리(`diskquota-2.4.so`)를 preload 하므로, RPM 업그레이드 시 `diskquota_lib_version` 도 함께 변경해야 합니다.

### Optional Extension (`inventory/whpg_cluster.yml` 에서 `true`로 활성화)

| 변수 | 패키지명 | 설명 |
|------|----------|------|
| `install_postgis` | `edb-whpg7-postgis` | 지리정보 시스템 |
| `install_hll` | `edb-whpg7-hll` | 근사 집계 |
| `install_q3c` | `edb-whpg7-q3c` | 구면 천체 인덱스 |
| `install_pgsphere` | `edb-whpg7-pgsphere` | 구면 기하 |
| `install_pgfs` | `edb-whpg7-pgfs` | 파일시스템 접근 |
| `install_pgaa` | `edb-whpg7-pgaa` | 고급 감사 |
| `install_pgvector` | `edb-whpg7-pgvector` | 벡터 유사도 검색 (기본 true) |
| `install_vectorplus` | `edb-whpg7-vectorplus` | ivfplus 벡터 인덱스 (pgvector 필요) |
| `install_utl_raw` | `edb-whpg7-utl-raw` | Oracle UTL_RAW 호환 (orafce 필요) |
| `install_flowserver` | `whpg7-flow-server` | 워크플로우 서버 |

---

## Mirror 구성 (Phase 3)

`gpinitsystem` 은 primary 만 만들고, `gpaddmirrors -i` 로 mirror 를 **segment 4대 단위 spread** 로 배치합니다
(`roles/whpg_init/tasks/mirrors.yml`, 규칙은 `templates/gpaddmirrors_config.j2`). segment 2 / 3대도 mirror 를 구성합니다.

- `inventory/hosts` 의 `[segments]` 를 적힌 순서대로 묶고, mirror 는 같은 그룹 안에만 둡니다.
  첫 그룹은 `whpg_mirror_first_group_size`(= min(호스트 수, 4))대, 이후 `whpg_mirror_group_size`(4)대씩입니다.
  → 2대: [2], 3대: [3], 4대: [4], 8대: [4][4]
- 호스트당 segment 수는 `whpg_segments_per_host` (2 / 4 / 8 …, 데이터 볼륨 수의 배수).
  데이터 볼륨이 1개(`/data`)면 모두 `/data` 아래, 2개(`/data1`, `/data2`)면 k 번째 segment 를 번갈아 둡니다.
  mirror 도 같은 k 의 디렉토리를 쓰므로 볼륨마다 primary / mirror 수가 같습니다. Coordinator / Standby 는 첫 번째 볼륨에 둡니다.
- 그룹(크기 S) 내 순번 h 호스트의 k 번째 primary mirror → 같은 그룹 `(h + (k mod (S-1)) + 1) mod S` 번째 호스트의 k 번째 mirror 슬롯
  (포트 `whpg_mirror_port_base + k`). 받는 호스트마다 k 가 하나씩이라 포트 / 디렉토리가 겹치지 않습니다.
  2대면 서로 상대 호스트에, 3대면 나머지 2대에 번갈아 둡니다.
- segment 호스트 수가 4의 배수도 2 / 3대도 아니거나(1, 5, 6, 7대 …), segment 수가 디스크 수의 배수가 아니면 `gpinitsystem` 전에 중단합니다.
- mirror 가 이미 있으면 건너뜁니다 (다시 실행해도 안전).

| `whpg_segments_per_host` | 볼륨 2개(/data1, /data2)일 때 볼륨마다 (1개면 /data 에 합산) | 호스트 1대 장애 시 넘겨받는 segment 수 |
|---|---|---|
| 2 | primary 1 + mirror 1 | 다음 2대에 1, 1 |
| 4 | primary 2 + mirror 2 | 나머지 3대에 2, 1, 1 |
| 8 | primary 4 + mirror 4 | 나머지 3대에 3, 3, 2 |

`whpg_segments_per_host: 2`, 4대(sdw1~4) 예시 (P=primary, M=mirror, 숫자=content):

| 호스트 | /data1 | /data2 |
|---|---|---|
| sdw1 | P0, M6 | P1, M5 |
| sdw2 | P2, M0 | P3, M7 |
| sdw3 | P4, M2 | P5, M1 |
| sdw4 | P6, M4 | P7, M3 |

볼륨 1개(`/data`), `whpg_segments_per_host: 2`, 4대 예시: 위 표의 /data1, /data2 칸을 합친 것과 같습니다 (예: sdw1 `/data` = P0, P1, M5, M6).

`whpg_segments_per_host: 2`, 2대 / 3대 예시:

| 호스트 (2대) | /data1 | /data2 |
|---|---|---|
| sdw1 | P0, M2 | P1, M3 |
| sdw2 | P2, M0 | P3, M1 |

| 호스트 (3대) | /data1 | /data2 |
|---|---|---|
| sdw1 | P0, M4 | P1, M3 |
| sdw2 | P2, M0 | P3, M5 |
| sdw3 | P4, M2 | P5, M1 |

- 2 / 3대는 호스트 1대 장애 시 나머지 1 / 2대가 그 primary 를 모두 넘겨받으므로 부하가 몰립니다.
- 증설은 `[segments]` 끝에 추가합니다. 2 / 3대는 먼저 4대까지(2→3, 2→4, 3→4) 증설하며 이때 기존 mirror 를 새 그룹 기준으로 재배치하고,
  4대 이후에는 4대 단위로 증설해 새 4대가 새 그룹이 됩니다 (sdw5~8 → 그룹 2, 기존 mirror 유지). 아래 Segment 증설 참고

## Segment 증설 (`playbooks/ops/expand_segments.yml`)

1. 새 호스트를 `inventory/hosts` 의 `[segments]` **끝에** 추가 (기존 순서 유지)
   - 기존 2 / 3대: 합계 4대까지 (2→3, 2→4, 3→4). 기존 mirror 를 증설 후 구성(전체 한 그룹)에 맞게 재배치
   - 기존 4대 이상: 4대 단위. 기존 mirror 는 그대로
2. 실행:

```bash
ansible-playbook playbooks/ops/expand_segments.yml                              # 추가 + 재분배 + 정리
ansible-playbook playbooks/ops/expand_segments.yml -e expand_redistribute=false # segment 추가까지만 (재분배는 나중에)
ansible-playbook playbooks/ops/expand_segments.yml -e expand_duration=04:00:00  # 재분배 최대 4시간
```

| 단계 | 대상 | 내용 |
|---|---|---|
| 1. 계획 | coordinator | `gp_segment_configuration` 과 `[segments]` 비교 → 새 호스트 결정. 증설 대수(2 / 3대 → 4대까지, 이후 4대 단위) / 기존 순서 / 포트 규칙 확인 |
| 2. /etc/hosts | 전체 | 새 호스트 등록 |
| 3. 준비 | 새 호스트 | `os_preconfig` → (SELinux / cgroup v2 적용에 필요하면) 재부팅 → `whpg_install` → extension RPM |
| 4. gpexpand | coordinator | hostfile 갱신, gpssh-exkeys → (기존 2 / 3대면) mirror 재배치 → `gpexpand -s -i` (새 primary + mirror, 초기 구성과 같은 그룹 spread) → PXF 등록 → 재분배 → `gpexpand -c` |
| 5. WEM | 전체 | `wem_enabled` 면 `07_wem.yml` (새 호스트 Host Agent / otelcol, pg_hba) |

- mirror 재배치(기존 2 / 3대, `roles/whpg_expand/tasks/remirror.yml`): 증설 후 전체 호스트를 한 그룹으로 보고 위치가 바뀌는 기존 mirror 만
  `gpmovemirrors` 로 옮깁니다. 최종 위치가 다른 segment 에 쓰이고 있으면 임시 위치(포트 +100, 디렉토리 `_mv`)를 거쳐 2단계로 옮기고,
  단계마다 모든 segment 동기화를 기다린 뒤 등록되지 않은 이전 mirror 디렉토리를 지웁니다.
  클러스터는 정지하지 않지만 옮기는 동안 해당 primary 는 이중화 없이 동작하고, mirror 전체를 복사하므로 데이터 크기만큼 시간이 걸립니다
  (`expand_remirror_sync_timeout`, 기본 4시간). 시작 전 모든 segment 가 up / 동기화 / 원래 역할이어야 합니다.
- 중간에 멈추거나 `expand_duration` 이 지나도 **같은 명령을 다시 실행**하면 `gpexpand.status` 를 보고 이어서 진행합니다
  (mirror 재배치도 현재 위치에서 다시 계산해 이어서 진행).
- 새 primary 는 content / dbid 를 현재 최대값 다음부터, 포트는 기존과 같은 `whpg_port_base + k` / `whpg_mirror_port_base + k` 를 씁니다.
- 변수: `roles/whpg_expand/defaults/main.yml` (`expand_redistribute`, `expand_duration`, `expand_parallel`, `expand_analyze`, `expand_cleanup`, `expand_reboot_if_needed`)

## WEM 구성 (Phase 7)

[edb-korea/wem-deploy](https://github.com/edb-korea/wem-deploy) 의 WEM 1.4 role 을 이 프로젝트 inventory 에 맞춰 반영했습니다.

```
[wem_host = wem_node 그룹 (기본 standby, 없으면 coordinator 로 지정)]
  ├─ whpg-enterprise-manager 1.4  (웹 wem_port=8080, Agent 8081)
  └─ ClickHouse                   (9000 / 8123) ← 메트릭 / 로그 저장 (acp_observability)

[모든 노드]
  ├─ edb-acp-host-agent  → WEM 에 자동 등록 (join-token 선등록, 수동 승인 불필요)
  └─ edb-otelcol         → 호스트 메트릭 / WHPG 로그 수집 → ClickHouse

[coordinator]  WEM 접속 계정 wemon (SCRAM), resource group wem_group, 상태 DB "wem"
[standby]      DB 메트릭(sqlquery) 수집 (coordinator failover 대비)
```

- **VIP 사용** (`wem_use_vip`, 기본 = `coordinator_ha_enabled`): WEM 의 WHPG / 상태 DB 접속(`wem.conf` 의 `WHPG_HOST`, `WEM_HOST`)과
  standby 의 DB 메트릭 수집이 `coordinator_vip` 로 접속합니다. failover 후에도 승격된 standby 로 이어서 접속합니다.
  그래서 WEM 은 HA(Phase 6) 이후 Phase 7 에서 설치하며, VIP 가 coordinator 에 올라와 있지 않으면 시작 전에 중단합니다.

- 패키지는 다른 RPM 과 같이 Controller 의 `local_rpm_dir` 우선 → dnf fallback 으로 설치합니다.
  필요 패키지: `whpg-enterprise-manager`, `edb-clickhouse-common-static/server/client`, `edb-acp-host-agent`, `edb-otelcol`
- WEM 1.2/1.3(Prometheus / Loki / Alertmanager / Alloy / observability-collector)이 설치되어 있으면 먼저 삭제합니다 (`wem_cleanup_legacy: auto`).
  `whpg-enterprise-manager` 가 1.4(`wem_remove_min_version`) 이상이면 1.2/1.3 으로 보지 않습니다.
  이때 WHPG 의 1.2/1.3 상태 DB(`wem`)도 삭제하므로, 보존하려면 `wem_drop_old_state_db_in_whpg: false`.
- 다시 실행해도 WEM 의 cookie / join secret 을 유지하고, 설정이 바뀐 서비스만 재시작합니다.
  `-t upgrade` 로 `wem_version` 보다 높은 WEM 이 설치되어 있으면 `wem_version` 으로 내리지 않습니다.
- `--check` 는 WEM 이 없는 호스트에서도 통과합니다 (설치 예정 패키지의 서비스 기동 / 확인, otelcol 조정은 건너뜀).
- RPM 업그레이드(`-t upgrade`)는 설치되어 있는 패키지만 dnf repo 의 최신 버전으로 올립니다 (`local_rpm_dir` 은 보지 않음).
  WEM host(ClickHouse → WEM)를 먼저 올리고, 모든 노드의 Host Agent / otelcol 을 한 대씩 올리며, 업그레이드된 서비스만 재시작합니다.
  대상은 `wem_upgrade_packages_wem_host` / `wem_upgrade_packages_all_hosts`. 결과는 마지막 Summary 에 표시됩니다.
- 접속: `http://<wem_host IP>:8080/` (admin / `vault_wem_admin_password`). **Management > Host Agents** 에서 모든 노드가 approved 인지 확인

```bash
ansible-playbook playbooks/07_wem.yml                       # 설치
ansible-playbook playbooks/07_wem.yml -e wem_use_vip=false  # VIP 대신 coordinator 실 IP 로 접속
ansible-playbook playbooks/07_wem.yml -t tune               # 일부 단계만
ansible-playbook playbooks/07_wem.yml -t upgrade --check    # WEM 관련 RPM 의 설치 / repo 최신 버전 확인만
ansible-playbook playbooks/07_wem.yml -t upgrade            # WEM 관련 RPM 을 repo 최신 버전으로 업그레이드
ansible-playbook playbooks/ops/remove_wem.yml               # 삭제 (확인 질문 없음, WEM 1.4 이상일 때만)
```

| tag | 태스크 파일 (`roles/wem/tasks/`) | 내용 |
|---|---|---|
| (always) | `00-checks.yml` | OS, VIP 활성 여부, 배치 출력 |
| `cleanup` | `01-cleanup-wem12.yml` | WEM 1.2/1.3 삭제 (감지된 경우만) |
| `pghba` | `03-pg-hba.yml` | coordinator / standby `pg_hba.conf` 에 wemon 허용 (`gpstop -u`) |
| `clickhouse` | `04-clickhouse.yml` | ClickHouse 설치 (wem_host) |
| `statedb` | `05-state-database.yml` | wemon 계정 / DB / resource group, (선택) 별도 상태 DB |
| `wem` | `06-wem.yml` | WEM 1.4 설치, `wem.conf` |
| `agent` | `07-host-agent.yml` | Host Agent / otelcol 설치, otelcol 조정 선적용, 자동 승인 |
| `tune` | `08-otelcol-tune.yml` | WEM 이 배포한 otelcol 설정과 병합 검사, 변경 시만 재시작 |
| `upgrade` | `upgrade.yml` | WEM 관련 RPM 을 repo 최신 버전으로 업그레이드 (`-t upgrade` 지정 시에만) |
| (always) | `10-summary.yml` | 서비스 상태 |

`-t agent` 는 `wem` 단계의 join secret 을 쓰므로 `-t wem,agent` 로 함께 실행합니다.
자주 바꾸는 변수는 `inventory/whpg_cluster.yml` 의 WEM 구역에 주석으로 적어 두었고, 전체 목록은 `roles/wem/defaults/main.yml` 에 있습니다.

---

## Coordinator HA 구성 (Phase 6)

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

## 업그레이드 (`playbooks/upgrade/upgrade.yml`)

[Minor upgrade 문서](https://www.enterprisedb.com/docs/warehousepg/latest/install_guide/minor_upgrade/) 절차를 따라
설치되어 있는 패키지를 dnf repo 의 최신 버전으로 올립니다 (`local_rpm_dir` 은 보지 않음). WEM 은 기존대로 `07_wem.yml -t upgrade`.

```bash
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=all --check      # 점검 + 변경 예정 사항 Summary (변경 없음)
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=all              # 전체
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=core             # warehouse-pg-7 + warehouse-pg-7-clients
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=pxf,backup       # 쉼표로 여러 개
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=extensions       # extension 전체
ansible-playbook playbooks/upgrade/upgrade.yml -e upgrade=postgis,pgaudit  # 개별 extension
```

| `-e upgrade=` | 패키지 | 절차 |
|---|---|---|
| `all` | 아래 전체 (설치된 것만) | core 가 포함되면 클러스터 정지 구간에 한 트랜잭션으로 모두 업그레이드 |
| `core` | `warehouse-pg-7` + `warehouse-pg-7-clients` (항상 함께) | 아래 core 절차 (서비스 중단) |
| `pxf` | `edb-whpg7-pxf` | `pxf cluster stop` → dnf → `pxf cluster register` → `pxf cluster start` → `ALTER EXTENSION pxf UPDATE` |
| `backup` | `whpg-backup` | dnf (gpbackup / gprestore 실행 중이면 중단) |
| `flowserver` | `whpg7-flow-server` | dnf (실행 중이면 중단, 업그레이드 후 수동 시작 + 잡 재제출) |
| `extensions` / `<이름>` | `whpg_extension_catalog` 의 나머지 (name 또는 pkg 로 지정) | 클러스터 정지 없이 dnf → `ALTER EXTENSION ... UPDATE`. preload 라이브러리(pgaudit, user_profile, diskquota 등)는 재시작해야 적용 (`-e whpg_upgrade_restart=true` 면 `gpstop -ra`) |

core 절차 (괄호는 문서 단계 번호):

1. 점검 (`--check` 에서도 실행): 7.4 이상, 7.5.0 이상이면 python3.11, FlowServer / gpbackup 미실행(16), 활성 세션(18, 모니터링 계정 `wemon` 제외),
   segment 동기화(19), gpadmin 외 crontab(7), gpadmin `.bashrc` / `.bash_profile` 의 `greenplum_path.sh`(28),
   server / clients 같은 목표 버전, 노드 간 버전 일치, dnf 테스트 트랜잭션(`tsflags=test`, 의존성 / 파일 충돌)
2. 업그레이드 전 상태 기록 `~gpadmin/whpg_upgrade_baseline_<시각>.txt` (10, 11)
3. gpadmin crontab 백업 / 제거 (6, 8) → `pxf cluster stop`(13) → pgBouncer(14) → WEM(15) → keepalived(standby → coordinator) 정지
4. `gpstop -a -M fast`(20) → 바이너리 백업 `/usr/edb/whpg7_save_<현재버전>` (21, 모든 노드) → dnf server + clients (25, 26)
5. 소유권 / symlink `/usr/local/greenplum-db`, `/usr/local/greenplum-db-clients` → `/usr/edb/whpg7` (27) → 모든 노드 버전 일치 확인
6. `gpstart -a`(29) → `pxf cluster register` → `ALTER EXTENSION gp_exttable_fdw / gp_toolkit UPDATE`(35, 36)
7. 7.6.x 권한 SQL (32~34, 모든 DB, template0 은 잠시 접속 허용 후 원복, `whpg_upgrade_post_sql`) → 버전 / `gpstate -f` / `gpstate -m` (30, 31)
8. crontab 복원(37) → keepalived(coordinator → standby) → `pxf cluster start`(38) → pgBouncer(39) → WEM(40). FlowServer(41)는 수동

- 점검에 문제가 있으면 `--check` 는 Summary 에 사유를 보여 주고, 실제 실행은 클러스터를 건드리기 전에 중단합니다. 실행 중 한 노드라도 실패하면 전체 중단.
- Summary: `--check` 는 변경 예정 사항(서비스 중단 여부, 순서, 대상 노드 / DB), 실행 시는 결과. 수동 작업(문서 1~5, 38, 41~45, 버전별 확인 사항)도 표시합니다.
- core 업그레이드 후 `inventory/whpg_cluster.yml` 의 `whpg_version` 을 새 버전으로 바꿉니다. diskquota 를 올리면 `diskquota_lib_version` 도 확인.
- 변수 (`roles/whpg_upgrade/defaults/main.yml`): `whpg_upgrade_post_sql`(_optional), `whpg_upgrade_backup_binaries`, `whpg_upgrade_force`(활성 세션이 있어도 진행),
  `whpg_upgrade_restart`, `whpg_upgrade_ignore_session_users`, `whpg_upgrade_services`, `whpg_upgrade_symlinks`, `whpg_upgrade_special`
- `playbooks/upgrade/upgrade_all.yml` / `upgrade_core.yml` / `upgrade_extensions.yml`, `playbooks/ops/minor_upgrade.yml` 은 이전 방식(`local_rpm_dir` / RPM 파일 지정)입니다.

---

## cluster diskquota (Phase 8, `playbooks/08_diskquota.yml`)

[whpg-diskquota](https://www.enterprisedb.com/docs/supported-open-source/warehousepg/extensions/additional/diskquota/) 2.4 의
cluster quota 로 모든 감시 DB 의 합계 사용량을 제한합니다. WHPG 구성 후 실행하는 post 작업입니다.

```bash
ansible-playbook playbooks/08_diskquota.yml --check   # 점검 + 변경 예정 사항 (변경 없음)
ansible-playbook playbooks/08_diskquota.yml           # 설정
ansible-playbook playbooks/08_diskquota.yml -e whpg_diskquota_soft_percent=85 -e whpg_diskquota_hard_percent=90
```

diskquota 의 cluster quota 는 값이 하나이고, soft / hard 는 같은 quota 에 대한 enforcement 방식입니다
(soft: 넘으면 새 쓰기 거부, 항상 on / hard: `diskquota.hard_limit=on` 이면 실행 중인 쿼리도 중단, reload 로 전환).
이를 이용해 두 기준을 다음과 같이 적용합니다.

| 변수 (기본) | 적용 |
|---|---|
| `whpg_diskquota_soft_percent` (90) | `diskquota.set_cluster_quota(기준 용량 × 90%)` → 넘으면 모든 감시 DB 에서 새 쓰기 거부 |
| `whpg_diskquota_hard_percent` (92) | 사용량(`show_cluster_quota_view`) ≥ 기준 용량 × 92% 이면 `diskquota.hard_limit=on` (실행 중인 쿼리도 중단), 90% 미만이면 off |
| `whpg_diskquota_hard_mode` (auto) | `auto`: coordinator / standby 의 gpadmin cron(`whpg_diskquota_check_interval_min` 분)이 위 기준으로 on / off (active coordinator 에서만 동작, 로그 `~gpadmin/gpAdminLogs/whpg_diskquota_check.log`, syslog `whpg_diskquota`), `on` / `off`: 고정 |
| `whpg_diskquota_capacity_gb` (0) | 기준 용량. 0 이면 segment 호스트 데이터 볼륨(`whpg_data_mounts`) 크기 합, mirror 가 있으면 ÷ 2 (diskquota 사용량은 primary 테이블 합계) |

설정 순서 (문서 Installing / Using 절차):

1. 모든 노드에 `edb-whpg7-diskquota`, `diskquota-2.4.so` 확인 (`diskquota_lib_version`)
2. `createdb diskquota` (launcher DB)
3. `shared_preload_libraries` 에 `diskquota-2.4` 추가 (기존 라이브러리 유지), `diskquota.max_monitored_databases` → 바뀐 경우에만 `gpstop -ar`
4. 모든 사용자 DB(`whpg_diskquota_exclude_databases` 제외)에 `CREATE EXTENSION diskquota` → `init_table_size_table()`
5. `set_cluster_quota()`, hard limit 설정 (auto 면 점검 스크립트 + cron)

- 다시 실행해도 바뀐 것만 적용합니다. **새 DB 를 만들거나 클러스터 증설 / 볼륨 변경 후에는 다시 실행**하세요 (extension, 기준 용량, quota 갱신).
- cluster quota 는 전체 합계 기준이라 특정 segment 에 데이터가 치우치면 그 디스크가 먼저 찰 수 있습니다. OS 단의 데이터 볼륨 quota(95%)가 마지막 방어선입니다.
- 확인: `SELECT * FROM diskquota.status();`, `SELECT * FROM diskquota.show_cluster_quota_view;`

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
4. **데이터 디스크**: `whpg_data_mounts[].device` 가 지정되면 빈 디스크만 mkfs.xfs 후 UUID 로 마운트 (xfs 외 데이터가 있으면 중단). 비어 있으면 기존 파일시스템 디렉토리를 사용. 어느 경우든 각 경로의 실제 물리 디스크를 조회해 I/O 스케쥴러/read-ahead udev 규칙 대상으로 사용
5. **PXF Hadoop**: `pxf_hadoop_enabled: true`이고 `pxf_namenode_host` 설정 시 core-site.xml 자동 배포
6. **RPM 패키지명**: 배포 환경에 따라 `warehousepg-*` 패키지명이 다를 수 있으므로 확인 후 수정

---

## 참고 문서

- [WarehousePG 설치 가이드](https://www.enterprisedb.com/docs/warehousepg/latest/install_guide/)
- [EDB 공식 Ansible 예제](https://www.enterprisedb.com/docs/warehousepg/latest/install_guide/ansible-example/)
- [WHPG 설치 가이드 (한국어 Tips)](https://github.com/unixfree/WarehousePG-Tip/blob/main/02.설치가이드.md)
- [Coordinator HA v2](https://github.com/unixfree/whpg_coordinator_ha_v2)
- [WEM 설치 가이드](https://www.enterprisedb.com/docs/supported-open-source/warehousepg/wem/installing/)
- [WEM 1.4 Ansible (edb-korea)](https://github.com/edb-korea/wem-deploy)
