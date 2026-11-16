# 班级功能（含班级练习）开发设计文档

> 目标系统: qduoj（OnlineJudge Django 1.11 后端 + OnlineJudgeFE Vue 前端 + JudgeServer/Judger 判题服务）  
> 文档性质: **纯设计文档，不含任何代码改动**  
> 编写日期: 2026-10-26  
> 依据: 对现有 4 个项目源码与 PostgreSQL 实际库结构的交叉验证结论（见 05-Database-Structure.md）

---

## 目录索引

1. [需求定义](#1-需求定义)
2. [方案选型](#2-方案选型)
3. [总体架构](#3-总体架构)
4. [数据库设计](#4-数据库设计)
5. [后端设计](#5-后端设计)
6. [判题链路改造](#6-判题链路改造)
7. [缓存设计](#7-缓存设计)
8. [前端设计](#8-前端设计)
9. [兼容性与风险评估](#9-兼容性与风险评估)
10. [实施计划](#10-实施计划)
11. [测试要点](#11-测试要点)
12. [扩展方向](#12-扩展方向)

---

## 1. 需求定义

### 1.1 功能需求

| # | 需求 | 说明 |
|---|------|------|
| R1 | 班级管理 | 管理员/教师创建班级、设置加入密码、维护成员名单 |
| R2 | 成员管理 | 教师添加/移除成员，用户凭密码自助加入，成员可退出 |
| R3 | **发布练习** | 教师在班级下创建练习（题集），从公共题库选题、设分值、排序，发布给学生 |
| R4 | 练习作答 | 学生在练习时间窗口内对练习题目提交代码，走完整判题流程 |
| R5 | 练习进度/排行 | 学生查看练习完成度排行；教师查看全班作答明细与导出 |
| R6 | 权限隔离 | 班级内容仅成员可见；练习未发布仅教师可见；与现有比赛/公开题库体系互不干扰 |

### 1.2 术语约定

| 术语 | 英文/代码标识 | 说明 |
|------|--------------|------|
| 班级 | Class | 由教师管理的教学单位 |
| 班级成员 | ClassMember | teacher（教师/助教）或 student（学生） |
| 练习 | Exercise | 班级下的一个题集/作业，可含时间窗口，支持 ACM/OI 两种计分 |
| 练习题目 | ExerciseProblem | 练习与公共题库 Problem 的关联（引用而非复制） |

### 1.3 明确不做（本期范围外）

- 班级公告、作业查重、补交审批、成绩单导出（列入[扩展方向](#12-扩展方向)）
- 不改动 JudgeServer 与 Judger（判题与练习无关，保持零侵入）

### 1.4 已确认产品决策（2026-10-26 定稿）

| # | 决策项 | 结论 | 影响章节 |
|---|--------|------|----------|
| D1 | OI 练习同题多次提交的计分 | **取最高分** | §5.6 排行算法 |
| D2 | 练习提交是否计入个人做题档案 | **计入**（`user_profile` 做题状态、accepted_number、题目统计照常更新） | §6.1 判题回写 |
| D3 | 删除班级时提交历史的处理 | **保留**：`submission.exercise_id` 外键采用 **on_delete=SET_NULL**，班级删除后提交记录仍在、归属置空 | §4.6、§5.5、§9-6 |

> D3 的连带影响（已纳入设计）：班级存续期间，练习提交**不出现在全站提交列表**（见 §5.5 改动点 4）；班级删除后孤儿提交（exercise_id=NULL）自然回到全站列表，且个人档案中的做题记录（D2 已计入）不受影响。

---

## 2. 方案选型

### 2.1 候选方案对比

| 维度 | 方案 A：独立 `class_group` 模块（推荐） | 方案 B：扩展现有 Contest 模块 |
|------|--------------------------------------|------------------------------|
| 实现方式 | 新建 Django app，班级/练习独立建模，练习题目用 M2M 引用公共题库 | Contest 表加 `class_id` 列，练习=挂在班级下的比赛 |
| 题目来源 | **直接引用题库现有题**（含教师私有题），一次管理 | 沿用比赛模式：题目需复制进"练习赛"（Problem 表加 exercise 类 FK），测试用例/SPJ 重复管理 |
| 复用度 | 复用 APIView/序列化器/判题管线/前端组件，业务代码独立 | 排行、密码、公告机制全部白拿 |
| 语义契合 | 练习=平时训练，题集可长期开放、反复练 | 比赛=限时竞技，结束即封闭，语义不符 |
| 侵入性 | 新增表为主，`submission` 表仅加 1 个可空列 | contest 全链路（视图/序列化器/dispatcher/前端）都要加分支判断 |
| 风险 | 判题回写链路需新增一个分支 | 现有比赛回归风险高 |

### 2.2 结论

**采用方案 A**。核心理由：

1. **练习的题目组织方式与比赛本质不同**：比赛题是"复制式"独立题（`Problem.contest_id` FK + 联合唯一索引 `(_id, contest_id)`，见 05 文档实测），练习应"引用式"复用题库（教师从已有题选题组卷），避免同一道题多份测试用例的维护负担；
2. **判题服务零改动**：Judger/JudgeServer 只关心 problem 维度，班级练习对其完全透明；
3. **对现有 20 张表只加 1 个可空列**，全部兼容性影响收敛到 submission 一处。

> 精确对应关系：练习的"权限校验/密码/时间窗口/排行语义"全部**照抄 Contest 的实现模式**（模式复用，代码独立）。

---

## 3. 总体架构

```
OnlineJudgeFE (Vue)
   │  新增路由: /class /class/:id /class/exercise/:id ...
   │  新增 api: src/pages/oj/api.js + src/pages/admin/api.js
   ▼
Django (OnlineJudge) —— 新增 app: class_group
   ├─ urls/oj.py        → /api/class/*          （学生/教师用户端）
   ├─ urls/admin.py     → /api/admin/class/*    （班级/练习管理）
   ├─ views/serializers → 参照 contest 模块结构
   ├─ submission 加 exercise_id FK（与 contest_id 同构）
   │
   │  提交进入后 → judge/dispatcher.py 派发（现有机制不动）
   ▼
JudgeServer (Flask) ──► Judger (C)     【零改动】
   │
   ▼ 判题完成回调（现有 message_queue 轮询）
Django dispatcher:
   ├─ update_problem / update_user_profile   ← 练习提交照常计入个人档案与题目统计
   └─ 新增分支: 失效练习排行缓存 cache.delete("class_exercise_rank:<id>")
```

**数据流要点**：练习提交与公开提交共用同一个提交→判题→回写管线，唯一差别是 `submission.exercise_id` 非空时多一步缓存失效。

---

## 4. 数据库设计

### 4.1 变更总览

| 变更 | 类型 | 对象 |
|------|------|------|
| 新增表 | 4 张 | `class_info`、`class_member`、`class_exercise`、`class_exercise_problem` |
| 修改表 | 1 张 | `submission` 新增可空列 `exercise_id` |
| 不新增 | 排行物化表 | 见 4.7 权衡：练习排行采用动态聚合 + 缓存，不建 rank 表 |
| 框架表 | 0 | 无新增（django_migrations 自动 +1 条） |

> 按项目实测惯例（05 文档）：AutoField → `integer + 序列`；DateTimeField → `timestamptz`；FK 约束为 `DEFERRABLE INITIALLY DEFERRED`（级联删除由 Django ORM 应用层实现）；bool/JSON 的 default 是应用层默认值，DB 无 DEFAULT 子句。

### 4.2 class_info — 班级

`db_table = "class_info"`（`class` 为 Python/SQL 保留字，故用 class_info）

| 字段 | Django 类型 | PG 类型 | 约束 | 说明 |
|------|------------|---------|------|------|
| id | AutoField | integer+序列 | PK | |
| name | TextField | text | NOT NULL | 班级名，如"2024级软工1班" |
| description | RichTextField | text | NOT NULL | 班级简介（XSS 过滤，同 Announcement） |
| join_password | TextField | text | NULL | 加入密码；**NULL=不开放自助加入**（只能教师添加） |
| visible | BooleanField | boolean | NOT NULL | 是否在班级广场公开展示 |
| created_by_id | FK(User) | integer FK | NOT NULL | 创建者（自动成为 teacher） |
| create_time | DateTimeField(auto_now_add) | timestamptz | NOT NULL | |
| last_update_time | DateTimeField(auto_now) | timestamptz | NOT NULL | |

**Meta**: `ordering = ("-create_time",)`；**索引**: `created_by_id`（教师查我的班级）

### 4.3 class_member — 班级成员

| 字段 | Django 类型 | PG 类型 | 约束 | 说明 |
|------|------------|---------|------|------|
| id | AutoField | integer+序列 | PK | |
| class_id | FK(ClassInfo) | integer FK | NOT NULL, **UNIQUE(class,user)** | |
| user_id | FK(User) | integer FK | NOT NULL | |
| role | TextField | text | NOT NULL | `"teacher"` / `"student"`（常量类 `ClassMemberRole`） |
| join_time | DateTimeField(auto_now_add) | timestamptz | NOT NULL | |

**Meta**: `unique_together = (("class", "user"),)`；**索引**: `class_id`、`user_id`（"我的班级"查询）

**角色判定规则**（唯一权威逻辑，写为 Model property `is_teacher`）：

```
is_teacher = (self.role == "teacher") or (self.user_id == class.created_by_id) or (user.admin_type == SUPER_ADMIN)
```

### 4.4 class_exercise — 练习

模式对齐 `contest.Contest`。

| 字段 | Django 类型 | PG 类型 | 约束 | 说明 |
|------|------------|---------|------|------|
| id | AutoField | integer+序列 | PK | |
| class_id | FK(ClassInfo) | integer FK | NOT NULL | 所属班级 |
| title | TextField | text | NOT NULL | 如"第三周练习：动态规划入门" |
| description | RichTextField | text | NOT NULL | 练习说明 |
| rule_type | TextField | text | NOT NULL | `"ACM"` / `"OI"`（复用 `ContestRuleType` 常量） |
| start_time | DateTimeField | timestamptz | NOT NULL | 开放时间 |
| end_time | DateTimeField | timestamptz | **NULL 可空** | NULL=长期开放（练习区别于比赛的关键点） |
| visible | BooleanField | boolean | NOT NULL | **发布开关**：false=草稿仅教师可见 |
| real_time_rank | BooleanField | boolean | NOT NULL | OI 练习是否实时显示分数排行（对齐 contest 同名字段） |
| created_by_id | FK(User) | integer FK | NOT NULL | 发布教师 |
| create_time / last_update_time | DateTimeField | timestamptz | NOT NULL | |

**Meta**: `ordering = ("-start_time",)`；**索引**: `class_id`

**状态计算属性**（对齐 contest 的 status，前端展示用）：
`not_start`（now < start）/ `underway`（start ≤ now < end 或 end 为 NULL）/ `ended`（end < now）

### 4.5 class_exercise_problem — 练习题目（M2M 中间表）

> 这是与 Contest 模式的**关键差异点**：引用公共题库，不复制题目。教师也可先在后台创建 `visible=False` 的私有题（现有 Problem.visible 字段天然支持），再挂进练习。

| 字段 | Django 类型 | PG 类型 | 约束 | 说明 |
|------|------------|---------|------|------|
| id | AutoField | integer+序列 | PK | |
| exercise_id | FK(ClassExercise) | integer FK | NOT NULL, **UNIQUE(exercise,problem)** | |
| problem_id | FK(Problem) | integer FK | NOT NULL | 引用题库题（含私有题） |
| order_index | IntegerField | integer | NOT NULL, default 0 | 展示顺序（题号 A/B/C…） |
| score | IntegerField | integer | NOT NULL, default 100 | OI 规则下该题分值（ACM 规则忽略） |

**Meta**: `unique_together = (("exercise", "problem"),)`、`ordering = ("order_index",)`；**索引**: `exercise_id`、`problem_id`

### 4.6 submission 表变更 — 新增 exercise_id

```sql
-- Django migration 自动生成，等价于：
ALTER TABLE submission ADD COLUMN exercise_id integer;   -- 可空
CREATE INDEX submission_exercise_id_idx ON submission (exercise_id);
-- FK: FOREIGN KEY (exercise_id) REFERENCES class_exercise(id) DEFERRABLE INITIALLY DEFERRED
-- Django 模型声明: exercise = models.ForeignKey(ClassExercise, null=True, on_delete=models.SET_NULL)
```

与现有 `contest_id`（integer，NULL，有索引）结构同构，**唯一差异是删除动作**（D3 决策）：

| 场景 | contest_id（现有） | exercise_id（本方案） |
|------|-------------------|----------------------|
| 删除比赛/班级时 | `on_delete=CASCADE` → 提交记录一并删除（ORM 级联） | `on_delete=SET_NULL` → **提交记录保留**，exercise_id 置空 |

`contest_id` 与 `exercise_id` 互斥，由应用层校验（见 5.5 提交校验）。

> 级联链说明：删除班级 → `class_exercise`（CASCADE）→ `submission.exercise_id`（**SET_NULL 断链**）→ 提交历史留存全库；`class_member`/`class_exercise_problem` 照常级联清空。

### 4.7 关于"排行表"的决策：不新建物化 rank 表

现有比赛用 `acm_contest_rank`/`oi_contest_rank` 物化表，由 dispatcher 在每次判题完成后事务更新（`_update_acm_contest_rank` 等方法，含 `select_for_update` 行锁与罚时计算）。

**练习不建物化表，改为请求时聚合 + Redis 缓存**，理由：

| 考量 | 比赛 | 班级练习 |
|------|------|----------|
| 数据规模 | 全校大型赛事，参与人多提交量大 | 单班 30~100 人 × 每题个位数提交 |
| 写放大 | 必须物化（排行榜 QPS 高） | 物化得不偿失：一张新表 + dispatcher 两个更新方法 + 行锁竞争 |
| 实现成本 | 已有 | 物化方案需移植 ACM/OI 两套 rank 更新逻辑 |
| 缓存失效 | dispatcher 直接更新物化行 | dispatcher 只删 1 个 Redis key，逻辑极简 |

**切换阈值**（写入运维文档）：单练习提交量超过 10 万或排行 API P95 > 500ms 时，再按 contest 模式增加 `class_exercise_rank` 物化表，届时 Rank API 接口签名不变、仅换实现。

### 4.8 表关系图（增量部分）

```
user ──────────┬──1:N── class_info (created_by)
               ├──1:N── class_exercise (created_by)
               └──M:N── class_info  (through class_member, role)
                                    │
class_info ──1:N── class_member ─────┘
          └──1:N── class_exercise ──1:N── class_exercise_problem ──N:1── problem
                        │
                        └──1:N── submission (submission.exercise_id 可空 FK)
```

与现有体系的关系：`problem` 表**零改动**（练习引用它）；`contest`/`acm_contest_rank` 等比赛表零改动。

---

## 5. 后端设计

### 5.1 新增 Django app 结构

按项目 app 惯例（参照 contest/）：

```
class_group/
├── __init__.py
├── models.py            # ClassInfo, ClassMember, ClassExercise, ClassExerciseProblem + 常量
├── serializers.py       # 用户端 + 管理端序列化器
├── urls/
│   ├── __init__.py
│   ├── oj.py            # /api/class/* 6~8 个路由
│   └── admin.py         # /api/admin/class/* 8 个路由
├── views/
│   ├── __init__.py
│   ├── oj.py            # 用户端视图
│   └── admin.py         # 管理端视图
├── permissions.py       # 装饰器（见 5.3）
├── rank.py              # 练习排行的动态聚合算法（见 5.6）
└── tests/               # 单测（见 11）
```

`oj/urls.py` 注册两行（模式与现有 include 完全一致）：

```
url(r"^api/", include("class_group.urls.oj")),
url(r"^api/admin/", include("class_group.urls.admin")),
```

`settings.py` 的 `INSTALLED_APPS` 追加 `"class_group"`。

### 5.2 模型常量定义（models.py）

```python
class ClassMemberRole:           # 参照 utils/constants.py 的 AdminType 风格
    TEACHER = "teacher"
    STUDENT = "student"

class ExerciseStatus:             # 参照 contest.constants ContestStatus
    NOT_START = "not_start"
    UNDERWAY = "underway"
    ENDED = "ended"
```

`rule_type` 直接复用 `contest.models.ContestRuleType`（ACM/OI），避免枚举漂移。

### 5.3 权限模型与装饰器

#### 5.3.1 权限矩阵（设计目标，测试用例据此编写）

| 操作 | 游客 | 普通用户(非成员) | student | teacher(非创建者) | 班级创建者 | Super Admin |
|------|------|----------------|---------|------------------|-----------|-------------|
| 创建班级 | ✗ | ✗（限 Admin 及以上） | ✗ | ✅ | ✅ | ✅ |
| 查看/编辑/删除班级 | ✗ | ✗（广场可见班级仅看 name/简介） | 看详情 | ✅（本班） | ✅ | ✅（全部） |
| 加/移成员、设助教 | ✗ | ✗ | ✗ | ✅（本班） | ✅ | ✅ |
| 自助加入班级 | ✗ | ✅（需密码时凭密码） | 已成员则拒绝 | — | — | — |
| 创建/编辑/发布练习 | ✗ | ✗ | ✗ | ✅（本班） | ✅ | ✅ |
| 查看"我的练习列表" | ✗ | ✗ | ✅（已发布） | ✅（含草稿） | ✅ | ✅ |
| 练习内提交代码 | ✗ | ✗ | ✅（窗口期内+已发布） | ✅ | ✅ | ✅ |
| 查看练习排行 | ✗ | ✗ | ✅（OI 未实时时仅自己成绩） | ✅ | ✅ | ✅ |
| 查看成员提交明细/导出 | ✗ | ✗ | 仅本人 | ✅（本班全部） | ✅ | ✅ |

#### 5.3.2 装饰器设计（`permissions.py`，模式照抄 `account/decorators.py` 的 `check_contest_permission`）

```
@class_permission_required(role_required=None)     # 校验是成员；role_required="teacher" 时校验教师
    参数: class_id 从 request.data 或 GET 中解析（模式同 check_contest_permission 解析 contest_id）
    语义: 装饰器查询 ClassMember，写入 request.user.class_role 供视图内复用
```

```
@create_class_required     # 等价 user.admin_type >= Admin（复用现有 check_user_admin_type(Admin) 即可）
```

**复用优先**：全局角色判断直接用 `account.decorators` 现有装饰器，不重写。

### 5.4 API 清单

#### 5.4.1 用户端（prefix `/api/`，全部参照 contest/urls/oj.py 命名风格）

| 方法+路径 | View 名 | 权限 | 请求参数 | 响应要点 |
|-----------|---------|------|----------|----------|
| GET `/api/classes/` | ClassListAPI | login_required | keyword | 班级广场：`visible=True` 的班级（仅 name/description，无成员数） |
| GET `/api/my_classes/` | MyClassListAPI | login_required | — | 我创建的 + 我加入的，含我在各班的 role |
| GET `/api/class/` | ClassAPI | member_required | `id` | 班级详情 + 成员数 + 练习数；非成员且班级 visible 时仅返回基本信息 |
| POST `/api/class/join/` | ClassJoinAPI | login_required | `class_id, password?` | 校验密码→创建 student 记录；重复加入/班级未开放返回错误 |
| DELETE `/api/class/member/` | ClassMemberExitAPI | login_required | `class_id` | 学生退出；teacher 角色不可退（需 Super Admin 移除） |
| GET `/api/class/member_list/` | ClassMemberListAPI | member_required | `class_id, limit, offset` | 成员列表（username/real_name/role/join_time），参照 UserList 分页 |
| GET `/api/class/exercises/` | ClassExerciseListAPI | member_required | `class_id, keyword?` | student 只见 `visible=True`；teacher 全见，含每练习题数与我的完成度 |
| GET `/api/class/exercise/` | ClassExerciseAPI | member_required | `id` | 练习详情 + 题目列表（`_id`、title、难度、score、我的状态）+ 状态枚举 |
| GET `/api/class/exercise/problem/` | ClassExerciseProblemAPI | member_required | `exercise_id, problem_id` | **题目详情**：member 可见被练习引用的私有题（关键点：不走公开题接口的 `visible=True` 过滤，而是校验 `class_exercise_problem` 中存在该关联），序列化复用 `ProblemSerializer` |
| GET `/api/class/exercise/submissions/` | ClassExerciseSubmissionListAPI | member_required | `exercise_id, limit, offset, myself?` | 学生默认见本人；teacher 见全部（对齐 contest_submissions 的封榜语义：OI 且非实时时学生仅见自己） |
| GET `/api/class/exercise_rank/` | ClassExerciseRankAPI | member_required | `exercise_id` | 动态排行（5.6），缓存 key 见 7 |

> 提交不设独立接口——**复用现有 `/api/submission/`**，`CreateSubmissionSerializer` 增加可选字段 `exercise_id`（与 `contest_id` 同构，见 5.5）。

#### 5.4.2 管理端（prefix `/api/admin/`）

| 方法+路径 | 权限 | 请求体 | 说明 |
|-----------|------|--------|------|
| GET/POST/PUT/DELETE `/api/admin/class/` | teacher_required（本班）/ Super Admin | POST: `name, description, join_password?, visible?` | CRUD；创建自动插入 teacher 成员记录；删除班级级联（ORM 级联练习/关联） |
| POST `/api/admin/class/member/` | teacher_required | `class_id, usernames[]`（数组） | 批量按用户名加学生；不存在/已存在逐条报明细 |
| DELETE `/api/admin/class/member/` | teacher_required | `class_id, user_id` | 移除成员（含助教）；**删除其在该班练习的 rank 缓存** |
| PUT `/api/admin/class/member/` | teacher_required | `class_id, user_id, role` | 升/降助教 |
| GET/POST/PUT/DELETE `/api/admin/class/exercise/` | teacher_required | POST: `class_id, title, description, rule_type, start_time, end_time?, visible, real_time_rank` | 练习 CRUD；**PUT `visible: true` 即"发布"动作** |
| GET/POST/PUT/DELETE `/api/admin/class/exercise_problem/` | teacher_required | POST: `exercise_id, problem_id, score?, order_index?` | 从题库选题；PUT 调序/改分；每变更后失效排行缓存 |
| GET `/api/admin/class/exercise/problem_selector/` | teacher_required | `exercise_id, keyword, limit, offset` | 选题器数据源：公开题 + 本人私有题（复用现有题目列表查询逻辑） |
| GET `/api/admin/class/exercise/download_submissions/` | teacher_required | `exercise_id` | 导出全班提交 zip（模式照抄 `DownloadContestSubmissions`） |

#### 5.4.3 统一响应格式

沿用 `utils/api/APIView`：`{"error": null, "data": ...}`；分页沿用 `paginate_data()`（limit≤250）；错误用 `self.error(msg, err)`。

### 5.5 提交链路改造（submission 模块最小侵入）

**改动点共 4 处**（1~3 对齐 contest_id 的既有写法；第 4 处由 D2/D3 决策引出的必要行为修正）：

1. **`submission/serializers.py`**：`CreateSubmissionSerializer` 增加一行 `exercise_id = serializers.IntegerField(required=False)`（照抄 `contest_id` 行）
2. **`submission/views/oj.py` `SubmissionAPI.post`**：在现有 contest 校验之后增加对称分支：
   ```
   elif exercise_id:
       ① ClassExercise 存在且 visible=True（否则 "Exercise is not published"）
       ② member_required 校验（非成员 403："You are not a member of this class"）
       ③ 时间窗口校验（now < start_time → "Not started"；end_time 已过 → "Exercise ended"）
       ④ contest_id 与 exercise_id 同时存在 → "Conflict"（互斥校验，放最前）
       ⑤ submission.exercise_id = exercise_id（写库路径与 contest 分支同构）
   ```
3. **`submission/serializers.py` List 序列化器**：`exclude` 元组补 `"exercise"`（对齐现有 exclude `contest` 的写法，防止列表接口泄漏练习 ID 给非成员）
4. **`submission/views/oj.py` `SubmissionListAPI.get`（第 135 行）**：全站提交列表过滤条件
   ```python
   # 现状: submissions = Submission.objects.filter(contest_id__isnull=True)...
   # 改为: 练习存续期间，其提交不进入全站列表（与比赛提交互斥语义对齐）
   submissions = Submission.objects.filter(contest_id__isnull=True, exercise_id__isnull=True)...
   ```
   **必要性**：现有过滤只排除 `contest_id`，练习提交的 contest_id 为空，不加此过滤会直接出现在全站列表——泄漏私有题存在性与学生练习动态；且这直接影响 D3：班级删除置空后，孤儿提交（exercise_id=NULL）才回到全站列表，语义自洽（练习存续=班级内可见；班级已删=沉淀为个人历史）。
   练习内的提交浏览一律走 §5.4.1 的 `ClassExerciseSubmissionListAPI`（带成员权限与封榜语义）。

### 5.6 练习排行动态聚合算法（`class_group/rank.py`）

**输入**：exercise_id；**输出**：按 rule_type 排序的成员成绩列表。

```
1. 取 exercise + class_info；取关联题 class_exercise_problem（含 problem 分值表）
2. 取该班全部成员 user_id 集合 S
3. 查 submission: exercise_id=练习, user_id ∈ S, create_time ∈ [start_time, end_time?]
   按 (user_id, problem_id) 分组，单次遍历聚合：
   ACM: 每组内按时间序 → 首次 AC 时间(相对 start_time) + AC 前非编译错误次数(罚时 20min/次，同 contest 语义) + is_first_ac
   OI : 每组取**最高分**（D1 已确认）；未实时排行时仅本人可见成绩
4. 未提交的成员也输出 0 分记录（教师视角的"完成度"）
5. 排序: ACM → accepted_number desc, total_time asc；OI → total_score desc
6. 结果写 Redis 缓存（TTL 由调用处指定，见 7）
```

> **口径说明（D1+D2 组合的已知差异，非缺陷）**：OI 练习中，个人档案（`user_profile.oi_problems_status`，走现有 `add_score` 最新分覆盖逻辑）与练习排行（最高分）可能不同——档案记录"最近状态"（沿用公开提交口径），排行记录"最佳尝试"。两者语义各自成立，文档在此明示以免开发时误判为 bug。

**数据量评估**：100 成员 × 20 题 × 5 次提交 = 1 万行 submission 单次遍历聚合，PG 毫秒级，无需优化。

---

## 6. 判题链路改造

### 6.1 改动清单（仅 `judge/dispatcher.py` 一处）

现有流程（已实测源码确认）：

```
on_message → judge → 成功后:
    update_problem()               # 题目统计
    update_user_profile()          # 个人档案（非 contest 分支）
    update_contest_problem_status()# 比赛分支
    update_contest_rank()          # 比赛分支 + cache.delete(contest_rank_cache)
```

**新增对称分支** `update_exercise()`（在 contest 分支的 else 侧）：

```
def update_exercise(self):
    if not self.submission.exercise_id: return
    # 练习提交计入个人档案与题目统计（D2 已确认）——
    #   练习提交 contest_id 为空，天然走 update_user_profile()/update_problem()
    #   的"公开提交"分支，个人档案/题目统计零改动自然生效；
    #   故本方法只需做一件事：
    cache.delete(f"{CacheKey.class_exercise_rank}:{self.submission.exercise_id}")
```

**D2 已确认：练习提交计入个人做题档案**（`user_profile.acm/oi_problems_status["problems"]`、accepted_number/submission_number、题目 statistic_info 均照常更新）。实现上**零额外改动**——练习提交的 `contest_id` 为空，dispatcher 现有的非比赛分支自动生效（`update_user_profile` 走公开提交路径、`update_problem` 无差别累加）。与比赛的"不计入"形成互补：比赛=竞技成绩隔离，练习=平时训练沉淀。

### 6.2 Rejudge 支持

`submission/views/admin.py` 的 rejudge 逻辑对 contest 提交有过滤（仅非比赛），需同步放行 exercise 提交（一行过滤条件调整）；dispatcher 的 `update_exercise` 在 rejudge 回调中同样生效，排行缓存自动失效。

### 6.3 JudgeServer / Judger

**零改动**。判题请求由 language_config/problem 维度组装（`judge/dispatcher.py` 侧），exercise 信息根本不出现在判题协议中。

---

## 7. 缓存设计

`utils/constants.py` 的 `CacheKey` 增加一个常量（模式照抄 `contest_rank_cache`）：

```python
class CacheKey:
    contest_rank_cache = "contest_rank_cache"
    class_exercise_rank = "class_exercise_rank"     # 新增, 拼接规则: f"{key}:{exercise_id}"
```

| 项 | 设计 |
|----|------|
| Key | `class_exercise_rank:<exercise_id>` |
| Value | rank.py 聚合结果（list of dict，JSON 序列化） |
| DB | Redis db1（沿用 CACHES["default"]，无需新配置） |
| 写入 | ClassExerciseRankAPI 命中缓存直接返回；miss 时聚合后 set |
| TTL | **600 秒**（比 contest 的"手工失效为主"多一层兜底过期，防极端情况下的脏数据永久滞留） |
| 失效时机（三处） | ① dispatcher 判题完成；② 管理端变更练习题目/成员/发布状态；③ rank API 支持 teacher `force_refresh=1`（对齐 contest 同名参数） |

---

## 8. 前端设计（OnlineJudgeFE）

### 8.1 路由（`src/router`，模式对齐现有 contest 路由）

| 路径 | 页面 | 复用组件 |
|------|------|----------|
| `/class` | 班级广场 + 我的班级（tab 切换） | Panel/DataTable |
| `/class/:classId` | 班级详情（练习 tab / 成员 tab） | — |
| `/class/exercise/:exerciseId` | 练习详情（题目列表 + 说明） | 复用 ContestProblemList 风格表格 |
| `/class/exercise/:exerciseId/problem/:problemId` | 练习题目页 | **直接复用** `Problem.vue` 组件族（题面/提交/统计），仅数据源换接口 |
| `/class/exercise/:exerciseId/rank` | 练习排行 | 复用 ACM/OI 排行表格组件 |
| `/admin/class` | 班级管理列表 | — |
| `/admin/class/:classId/exercise/new`、`/edit/:exerciseId` | 练习创建/编辑 + 选题器 | Simditor（富文本）、现有题目选择器交互 |
| `/admin/class/:classId/member` | 成员管理（批量加人/助教） | 参照 generate_user 的批量表单 |

### 8.2 api.js 增量

| 文件 | 新增函数（示例签名） |
|------|---------------------|
| `src/pages/oj/api.js` | `getClassList` / `getMyClasses` / `joinClass` / `getClassExerciseList` / `getExerciseProblem` / `getExerciseSubmissionList` / `getExerciseRank` …（约 10 个，封装规则同现有 ajax()） |
| `src/pages/admin/api.js` | `createClass/editClass/deleteClass` / `addMembers/removeMember/setMemberRole` / `createExercise/publishExercise` / `addExerciseProblem/removeExerciseProblem` / `downloadExerciseSubmissions` …（约 12 个） |

### 8.3 交互要点

- **发布练习** = 管理端练习编辑页 `visible` 开关置 true；未发布练习在学生端任何接口/页面均不可见（后端强控，前端只是表现）
- 练习列表为空状态、时间窗口未开始的禁用提交按钮等细节，对齐 Contest 列表的 status 展示逻辑

---

## 9. 兼性与风险评估

| # | 风险点 | 等级 | 缓解措施 |
|---|--------|------|----------|
| 1 | `submission` 表加列：全库最大写入频率的表 | 中 | 仅加**可空列+索引**，PG 11+ 加列不重写表；上线窗口执行 migration，停写时间 < 1s |
| 2 | 提交接口加 `exercise_id` 参数影响现有提交 | 低 | 字段 required=False，老前端不传该字段行为完全不变；`contest_id` 同现互斥校验 |
| 3 | dispatcher 新分支影响判题回写主链路 | 中 | 新分支为独立方法、首行判空 return；灰度期日志监控 `exercise_id` 非空提交量 |
| 4 | 排行缓存脏读（判题完成但缓存未失效） | 低 | 双保险：三处失效点 + 600s TTL；teacher 端 force_refresh 兜底 |
| 5 | 私有题借练习泄漏到非成员 | 中 | ExerciseProblemAPI 强制 member_required + 关联表存在性校验，不走公开题接口的 visible 过滤；测试矩阵覆盖"已知 problem_id 直接请求"场景 |
| 6 | 班级/练习删除的数据清理 | 低 | 删班级：练习/关联/成员级联清空（ORM 级联，见 05 文档 FK 行为）；**提交历史保留（D3 已确认）**——`submission.exercise_id` 用 SET_NULL 断链。已知连带行为：置空后的孤儿提交回到全站提交列表（题目内容仍受 `problem.visible` 保护，列表仅暴露 _id/用户名/结果，与现有私有题提交同等的暴露面）；若产品后续认为不可接受，退路是"软删除班级"（加 is_deleted 标记）而非推翻本设计 |
| 7 | 与比赛功能交叉（用户在比赛期间又交练习） | 低 | submission 单条记录天然归属唯一容器（contest_id/exercise_id/公开 三选一），无交叉污染 |

**回滚方案**：功能整体开关化——若需紧急回滚，前端隐藏入口 + 后端 `SubmissionAPI.post` 对 exercise_id 提前返回错误即可，表结构无需回滚（可空列不不影响任何现有逻辑）。

---

## 10. 实施计划

| 阶段 | 内容 | 交付物 | 预估 |
|------|------|--------|------|
| P1 | 后端基座 | `class_group` app + 4 张表 migration + admin CRUD API + 单测 | 2~3 人日 |
| P2 | 提交链路 | submission serializer/视图改造 + dispatcher 分支 + rejudge 放行 + 缓存失效 + 集成测试 | 1~2 人日 |
| P3 | 用户端 | 练习列表/题目详情/提交/排行 API + rank.py 聚合算法 + OI 非实时成绩遮挡测试 | 2~3 人日 |
| P4 | 前端学生侧 | 班级广场/我的班级/练习详情/排行 5 个页面 | 2~3 人日 |
| P5 | 前端教师侧 | 班级管理/成员管理/练习编辑与选题器/导出 | 3 人日 |
| P6 | 回归与上线 | 全量回归（比赛/公开题/提交）+ 权限矩阵测试 + 灰度 | 1~2 人日 |

**关键依赖顺序**：P1→P2 强串行（表和提交链路是地基）；P3/P4/P5 可并行（前后端接口先行约定，见 5.4 表格即接口契约）。

---

## 11. 测试要点

### 11.1 权限矩阵测试（P1/P3 必测，对应 5.3.1 表格逐格）

重点用例：
- 非成员请求练习题目详情（携带合法 problem_id）→ 403
- student 请求未发布练习 → 404/403（且列表接口不可见）
- teacher 移除自己（创建者）→ 拒绝
- 普通用户创建班级 → 403；Admin 创建 → 200
- 练习中提交 contest_id 与 exercise_id 同传 → "Conflict"

### 11.2 业务规则测试

| 场景 | 断言 |
|------|------|
| ACM 练习：WA×2 → AC | rank 中 error_number=2，total_time = ac_time + 40min |
| OI 练习：多次提交同题（60 分→90 分→70 分） | 排行取**最高分 90**（D1）；个人档案按现有覆盖逻辑为 70（口径差异见 §5.6 说明） |
| 练习提交计入档案（D2） | 提交后 `user_profile.accepted_number`/`acm_problems_status["problems"]` 更新，题目 `statistic_info` 累加 |
| 练习存续期提交的可见性 | 该提交**不出现在**全站 `/api/submissions/` 列表；出现在练习自己的 `exercise_submissions` 列表 |
| end_time=NULL 练习 | 状态恒为 underway，可持续提交 |
| 发布后教师改题/撤题 | 排行缓存失效，下次请求重算（用 cache.set 手动验证） |
| 删除班级（D3） | 练习/关联/成员全部级联消失；**submission 保留且 exercise_id 置空**；此后这些孤儿提交出现在全站提交列表 |
| 判题完成回调 | 练习排行缓存被删（检查 redis-cli TTL/EXISTS） |
| Rejudge 练习提交 | 走通且排行刷新 |

### 11.3 回归测试（确保零破坏）

现有比赛/公开题库/提交流程的全量回归（重点：`CreateSubmissionSerializer` 加字段后老前端提交、contest 提交封榜逻辑、contest_rank 缓存失效逻辑）。

---

## 12. 扩展方向（本期不实现，架构预留）

| 方向 | 预留点 |
|------|--------|
| 班级公告 | `class_announcement` 表照抄 contest_announcement，本次不做 |
| 作业查重 | submission.code 已存全量，可在导出链路后置加比对 |
| 练习到期补交 | `class_exercise` 加 `allow_late` 字段，提交校验分支放宽 |
| 成长档案报表 | user_profile 已有 acm/oi_problems_status JSONB，按 class 过滤即可统计 |
| 与比赛打通 | 无需打通：练习题即公共题库题，可直接被比赛引用（同题引用天然支持） |
| 大规模物化排行 | 见 4.7 切换阈值，Rank API 契约不变 |

---

## 附：设计对照索引（本方案 ↔ 现有代码）

| 本方案设计 | 对照的现有实现 |
|-----------|---------------|
| APIView / success/error/paginate | `utils/api/api.py` |
| 装饰器 `@class_permission_required` | `account/decorators.py` `check_contest_permission` |
| 班级密码加入 | `contest/views/oj.py` `ContestPasswordVerifyAPI` |
| 练习模型与状态属性 | `contest/models.py` `Contest.status/contest_type` |
| 题目关联表 | `problem_tags`（M2M 中间表实测结构，05 文档） |
| `exercise_id` 字段接入 | `CreateSubmissionSerializer.contest_id`（submission/serializers.py:10） |
| 排行语义（罚时/首A/OI 分） | `judge/dispatcher.py` `_update_acm_contest_rank` / `_update_oi_contest_rank` |
| 缓存 key 常量 | `utils/constants.py` `CacheKey.contest_rank_cache` |
| 教师导出提交 | `contest/views/admin.py` `DownloadContestSubmissions` |
| 练习题目详情可见性 | `contest/views/oj.py` `ContestProblemAPI`（比赛题不走公开 visible 过滤） |
