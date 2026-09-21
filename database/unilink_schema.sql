-- ============================================================================
-- UniLink — Campus Platform Database Schema
-- MySQL 8.0.16+ | InnoDB | utf8mb4 / utf8mb4_unicode_ci
-- ============================================================================
-- FRESH INSTALL ONLY: creates tables, constraints, indexes and demo data.
-- This is not a migration or a repeatable seed script. Existing installations
-- need a separately reviewed ALTER/data migration; do not drop existing data.
-- Store DATETIME values in UTC; render campus times in the application.
-- Authorization (account roles, campus scope, accepted study connections),
-- capacity reservations and moderation transitions require backend enforcement.
-- UI counts, ranks, match scores and profile completeness are derived values.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS unilink
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE unilink;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ============================================================================
-- 1. universities
-- ============================================================================
CREATE TABLE universities (
    university_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(150)    NOT NULL,
    email_domain    VARCHAR(100)    NOT NULL,
    location        VARCHAR(150)    NOT NULL,
    logo_url        VARCHAR(500)    NULL,
    status          ENUM('active','inactive') NOT NULL DEFAULT 'active',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_universities_name UNIQUE (name),
    CONSTRAINT uq_universities_email_domain UNIQUE (email_domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 2. users  (single central authentication table for all account types)
-- ============================================================================
CREATE TABLE users (
    user_id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(150)    NOT NULL,
    email           VARCHAR(190)    NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    account_type    ENUM('student','recruiter','university_admin','super_admin') NOT NULL,
    account_status  ENUM('pending_verification','pending_approval','active','suspended','rejected')
                        NOT NULL DEFAULT 'pending_verification',
    email_verified  TINYINT(1)      NOT NULL DEFAULT 0,
    avatar_url      VARCHAR(500)    NULL,
    last_seen_at    DATETIME        NULL,
    terms_accepted_at DATETIME      NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_email UNIQUE (email),
    KEY idx_users_account_type (account_type),
    KEY idx_users_account_status (account_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Main campus feed posts
CREATE TABLE posts (
    post_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    author_id BIGINT UNSIGNED NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (author_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    KEY idx_posts_created (created_at), KEY idx_posts_author (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 3. student_profiles
-- ============================================================================
CREATE TABLE student_profiles (
    user_id             BIGINT UNSIGNED PRIMARY KEY,
    university_id       BIGINT UNSIGNED NOT NULL,
    student_id          VARCHAR(50)     NOT NULL,
    department          VARCHAR(100)    NOT NULL,
    semester            VARCHAR(20)     NULL,
    cgpa                DECIMAL(4,2)     NULL,
    cgpa_scale          DECIMAL(4,2)     NOT NULL DEFAULT 4.00,
    location            VARCHAR(150)    NULL,
    enrollment_term     VARCHAR(30)     NULL,
    graduation_year     YEAR            NULL,
    resume_url          VARCHAR(500)    NULL,
    github_url          VARCHAR(500)    NULL,
    linkedin_url        VARCHAR(500)    NULL,
    portfolio_url       VARCHAR(500)    NULL,
    bio                 TEXT            NULL,
    profile_picture_url VARCHAR(500)    NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_student_profiles_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_profiles_university
        FOREIGN KEY (university_id) REFERENCES universities(university_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_student_profiles_university_student UNIQUE (university_id, student_id),
    CONSTRAINT chk_student_cgpa CHECK (cgpa_scale > 0 AND (cgpa IS NULL OR cgpa BETWEEN 0 AND cgpa_scale)),
    KEY idx_student_profiles_university (university_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 4. university_admins
-- ============================================================================
CREATE TABLE university_admins (
    user_id        BIGINT UNSIGNED NOT NULL,
    university_id  BIGINT UNSIGNED NOT NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, university_id),
    CONSTRAINT fk_university_admins_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_university_admins_university
        FOREIGN KEY (university_id) REFERENCES universities(university_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 5. email_otps
-- ============================================================================
CREATE TABLE email_otps (
    otp_id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT UNSIGNED NOT NULL,
    otp_hash    VARCHAR(255)    NOT NULL,
    purpose     ENUM('email_verification','password_reset') NOT NULL DEFAULT 'email_verification',
    attempts    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    expires_at  DATETIME        NOT NULL,
    used_at     DATETIME        NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_email_otps_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    KEY idx_email_otps_user_expires (user_id, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 6. courses
-- ============================================================================
CREATE TABLE courses (
    course_id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    university_id  BIGINT UNSIGNED NOT NULL,
    course_code    VARCHAR(20)     NOT NULL,
    course_name    VARCHAR(150)    NOT NULL,
    department     VARCHAR(100)    NOT NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_courses_university
        FOREIGN KEY (university_id) REFERENCES universities(university_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_courses_university_code UNIQUE (university_id, course_code),
    KEY idx_courses_university (university_id),
    KEY idx_courses_course_code (course_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 7. student_courses  (junction — used for study-partner matching)
-- ============================================================================
CREATE TABLE student_courses (
    user_id            BIGINT UNSIGNED NOT NULL,
    course_id          BIGINT UNSIGNED NOT NULL,
    academic_semester  VARCHAR(20) NOT NULL,
    section_number     VARCHAR(30) NULL,
    instructor_name    VARCHAR(150) NULL,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, course_id, academic_semester),
    CONSTRAINT fk_student_courses_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_courses_course
        FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 8. resources  (core academic resource-sharing table)
-- ============================================================================
CREATE TABLE resources (
    resource_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uploaded_by          BIGINT UNSIGNED NOT NULL,
    course_id            BIGINT UNSIGNED NOT NULL,
    title                VARCHAR(200)    NOT NULL,
    resource_type        ENUM('notes','past_exam','assignment','slides','question_bank','lab_report','formula_sheet','other') NOT NULL,
    academic_semester    VARCHAR(20)     NULL,
    description          TEXT            NULL,
    file_url             VARCHAR(500)    NOT NULL,
    original_file_name   VARCHAR(255)    NULL,
    mime_type            VARCHAR(100)    NULL,
    file_size            BIGINT UNSIGNED NULL,
    page_count           INT UNSIGNED NULL,
    section_instructor   VARCHAR(200) NULL,
    integrity_confirmed_at DATETIME NULL,
    visibility           ENUM('university','public') NOT NULL DEFAULT 'university',
    verification_status  ENUM('unreviewed','peer_verified','faculty_reviewed') NOT NULL DEFAULT 'unreviewed',
    download_count       INT UNSIGNED    NOT NULL DEFAULT 0,
    status               ENUM('draft','pending_review','active','rejected','removed') NOT NULL DEFAULT 'pending_review',
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_resources_uploader
        FOREIGN KEY (uploaded_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_resources_course
        FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    KEY idx_resources_course (course_id),
    KEY idx_resources_uploaded_by (uploaded_by),
    KEY idx_resources_type (resource_type),
    KEY idx_resources_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 9. skills
-- ============================================================================
CREATE TABLE skills (
    skill_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    skill_name  VARCHAR(100) NOT NULL,
    CONSTRAINT uq_skills_name UNIQUE (skill_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 10. student_skills  (junction)
-- ============================================================================
CREATE TABLE student_skills (
    user_id   BIGINT UNSIGNED NOT NULL,
    skill_id  BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (user_id, skill_id),
    CONSTRAINT fk_student_skills_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_student_skills_skill
        FOREIGN KEY (skill_id) REFERENCES skills(skill_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 11. study_partner_requests
-- ============================================================================
CREATE TABLE study_partner_requests (
    request_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sender_id    BIGINT UNSIGNED NOT NULL,
    receiver_id  BIGINT UNSIGNED NOT NULL,
    message      VARCHAR(500) NULL,
    status       ENUM('pending','accepted','declined','cancelled') NOT NULL DEFAULT 'pending',
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- ON UPDATE RESTRICT (not CASCADE) here: MySQL does not allow a column
    -- covered by an ON UPDATE CASCADE referential action to also appear in
    -- a CHECK constraint. user_id is an AUTO_INCREMENT PK and is never
    -- updated in practice, so RESTRICT has no real-world effect.
    CONSTRAINT fk_spr_sender
        FOREIGN KEY (sender_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_spr_receiver
        FOREIGN KEY (receiver_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT chk_spr_not_self CHECK (sender_id <> receiver_id),
    -- Prevents the same sender/receiver pair from having two requests in the
    -- same status simultaneously (e.g. two concurrent "pending" requests).
    CONSTRAINT uq_spr_sender_receiver_status UNIQUE (sender_id, receiver_id, status),
    KEY idx_spr_sender (sender_id),
    KEY idx_spr_receiver (receiver_id),
    KEY idx_spr_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 12. clubs
-- ============================================================================
CREATE TABLE clubs (
    club_id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    university_id     BIGINT UNSIGNED NOT NULL,
    club_name         VARCHAR(150)    NOT NULL,
    category          VARCHAR(100)    NOT NULL,
    tagline           VARCHAR(200)    NULL,
    description       TEXT            NULL,
    logo_url          VARCHAR(500)    NULL,
    cover_url         VARCHAR(500)    NULL,
    club_email        VARCHAR(190)    NULL,
    meeting_location  VARCHAR(150)    NULL,
    founded_year      YEAR            NULL,
    meeting_schedule  VARCHAR(200)    NULL,
    recruitment_open TINYINT(1)      NOT NULL DEFAULT 0,
    recruitment_term VARCHAR(30)     NULL,
    is_featured       TINYINT(1)      NOT NULL DEFAULT 0,
    verified_at       DATETIME        NULL,
    charter_expires_on DATE           NULL,
    affiliation       VARCHAR(200)    NULL,
    faculty_advisor_name VARCHAR(150) NULL,
    faculty_advisor_department VARCHAR(150) NULL,
    advisor_approved_at DATETIME NULL,
    github_url        VARCHAR(500) NULL,
    linkedin_url      VARCHAR(500) NULL,
    facebook_url      VARCHAR(500) NULL,
    status            ENUM('pending','active','rejected','suspended') NOT NULL DEFAULT 'pending',
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_clubs_university
        FOREIGN KEY (university_id) REFERENCES universities(university_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_clubs_university_name UNIQUE (university_id, club_name),
    KEY idx_clubs_university (university_id),
    KEY idx_clubs_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 13. club_memberships
-- club_memberships.role = 'admin' is how a student becomes a club admin —
-- no separate club_admin account type exists.
-- ============================================================================
CREATE TABLE club_memberships (
    club_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    role       ENUM('member','admin') NOT NULL DEFAULT 'member',
    position_title VARCHAR(100) NULL,
    team_name VARCHAR(100) NULL,
    committee_term VARCHAR(30) NULL,
    committee_order SMALLINT UNSIGNED NULL,
    status     ENUM('active','pending','removed') NOT NULL DEFAULT 'pending',
    joined_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (club_id, user_id),
    CONSTRAINT fk_club_memberships_club
        FOREIGN KEY (club_id) REFERENCES clubs(club_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_club_memberships_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 14. club_events
-- ============================================================================
CREATE TABLE club_events (
    event_id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id             BIGINT UNSIGNED NOT NULL,
    created_by          BIGINT UNSIGNED NOT NULL,
    title               VARCHAR(200)    NOT NULL,
    description         TEXT            NULL,
    event_date          DATE            NOT NULL,
    start_time          TIME            NULL,
    end_time            TIME            NULL,
    location            VARCHAR(200)    NULL,
    banner_url          VARCHAR(500)    NULL,
    registration_link   VARCHAR(500)    NULL,
    event_type          VARCHAR(100) NULL,
    academic_semester   VARCHAR(30) NULL,
    capacity            INT UNSIGNED NULL,
    registration_deadline DATETIME NULL,
    audience            ENUM('members','university','public') NOT NULL DEFAULT 'university',
    admission_fee       DECIMAL(10,2) NOT NULL DEFAULT 0,
    currency            CHAR(3) NOT NULL DEFAULT 'BDT',
    speaker_details     TEXT NULL,
    status              ENUM('draft','published','cancelled') NOT NULL DEFAULT 'draft',
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_club_events_club
        FOREIGN KEY (club_id) REFERENCES clubs(club_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_club_events_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    KEY idx_club_events_club (club_id),
    KEY idx_club_events_date (event_date),
    KEY idx_club_events_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 15. club_announcements
-- ============================================================================
CREATE TABLE club_announcements (
    announcement_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id          BIGINT UNSIGNED NOT NULL,
    created_by       BIGINT UNSIGNED NOT NULL,
    title            VARCHAR(200) NOT NULL,
    content          TEXT         NOT NULL,
    pinned           TINYINT(1)   NOT NULL DEFAULT 0,
    audience         ENUM('members','university','public') NOT NULL DEFAULT 'university',
    category         VARCHAR(100) NULL,
    attachment_url   VARCHAR(500) NULL,
    attachment_name  VARCHAR(255) NULL,
    attachment_size  BIGINT UNSIGNED NULL,
    status           ENUM('published','removed') NOT NULL DEFAULT 'published',
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_club_announcements_club
        FOREIGN KEY (club_id) REFERENCES clubs(club_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_club_announcements_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    KEY idx_club_announcements_club (club_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 16. companies
-- ============================================================================
CREATE TABLE companies (
    company_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    company_name  VARCHAR(150) NOT NULL,
    contact_email VARCHAR(190) NULL,
    contact_name  VARCHAR(150) NULL,
    portal_code   VARCHAR(50) NULL,
    website       VARCHAR(300) NULL,
    industry      VARCHAR(100) NULL,
    location      VARCHAR(150) NULL,
    description   TEXT NULL,
    logo_url      VARCHAR(500) NULL,
    status        ENUM('pending','active','rejected','suspended') NOT NULL DEFAULT 'pending',
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_companies_name UNIQUE (company_name),
    KEY idx_companies_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 17. company_recruiters
-- ============================================================================
CREATE TABLE company_recruiters (
    company_id  BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (company_id, user_id),
    CONSTRAINT fk_company_recruiters_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_company_recruiters_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 18. jobs
-- ============================================================================
CREATE TABLE jobs (
    job_id                 BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    company_id             BIGINT UNSIGNED NOT NULL,
    posted_by              BIGINT UNSIGNED NOT NULL,
    title                  VARCHAR(200) NOT NULL,
    job_type               ENUM('internship','full_time','part_time') NOT NULL,
    location               VARCHAR(150) NULL,
    description            TEXT NOT NULL,
    required_skills        VARCHAR(500) NULL,
    work_mode              ENUM('on_site','remote','hybrid') NOT NULL DEFAULT 'on_site',
    salary_min             DECIMAL(12,2) NULL,
    salary_max             DECIMAL(12,2) NULL,
    salary_currency        CHAR(3) NOT NULL DEFAULT 'BDT',
    salary_period          ENUM('hour','month','year','project') NOT NULL DEFAULT 'month',
    compensation_details   VARCHAR(500) NULL,
    duration_months        SMALLINT UNSIGNED NULL,
    minimum_cgpa           DECIMAL(4,2) NULL,
    benefits               TEXT NULL,
    is_featured            TINYINT(1) NOT NULL DEFAULT 0,
    application_url        VARCHAR(500) NULL,
    application_deadline   DATE NULL,
    status                 ENUM('draft','active','closed','removed') NOT NULL DEFAULT 'draft',
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_jobs_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_job_salary CHECK ((salary_min IS NULL OR salary_min >= 0) AND (salary_max IS NULL OR salary_max >= 0) AND (salary_min IS NULL OR salary_max IS NULL OR salary_max >= salary_min)),
    CONSTRAINT fk_jobs_poster
        FOREIGN KEY (posted_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    KEY idx_jobs_company (company_id),
    KEY idx_jobs_status (status),
    KEY idx_jobs_type (job_type),
    KEY idx_jobs_deadline (application_deadline),
    KEY idx_jobs_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 19. applications
-- ============================================================================
CREATE TABLE applications (
    application_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    job_id          BIGINT UNSIGNED NOT NULL,
    student_id      BIGINT UNSIGNED NOT NULL,
    resume_url      VARCHAR(500) NULL,
    transcript_url  VARCHAR(500) NULL,
    cover_letter    TEXT NULL,
    recruiter_notes TEXT NULL,
    status          ENUM('submitted','reviewing','shortlisted','interview','offered','accepted','rejected','withdrawn') NOT NULL DEFAULT 'submitted',
    applied_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_applications_job
        FOREIGN KEY (job_id) REFERENCES jobs(job_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_applications_student
        FOREIGN KEY (student_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_applications_job_student UNIQUE (job_id, student_id),
    KEY idx_applications_student (student_id),
    KEY idx_applications_job (job_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 20. university_announcements
-- ============================================================================
CREATE TABLE university_announcements (
    announcement_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    university_id    BIGINT UNSIGNED NOT NULL,
    created_by       BIGINT UNSIGNED NOT NULL,
    title            VARCHAR(200) NOT NULL,
    content          TEXT NOT NULL,
    important        TINYINT(1) NOT NULL DEFAULT 0,
    target_department VARCHAR(100) NULL,
    reference_code   VARCHAR(100) NULL,
    attachment_url   VARCHAR(500) NULL,
    published_at     DATETIME NULL,
    status           ENUM('draft','published','removed') NOT NULL DEFAULT 'draft',
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_university_announcements_university
        FOREIGN KEY (university_id) REFERENCES universities(university_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_university_announcements_creator
        FOREIGN KEY (created_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    KEY idx_university_announcements_university (university_id),
    KEY idx_university_announcements_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- 21. approval_requests  (Super Admin approval flow for companies & clubs)
-- ============================================================================
CREATE TABLE approval_requests (
    approval_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    request_type       ENUM('company','club') NOT NULL,
    requested_by       BIGINT UNSIGNED NOT NULL,
    company_id         BIGINT UNSIGNED NULL,
    club_id            BIGINT UNSIGNED NULL,
    status             ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
    reviewed_by        BIGINT UNSIGNED NULL,
    rejection_reason   VARCHAR(500) NULL,
    requested_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at        DATETIME NULL,
    CONSTRAINT fk_approval_requests_requester
        FOREIGN KEY (requested_by) REFERENCES users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_approval_requests_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    -- ON UPDATE RESTRICT (not CASCADE): company_id/club_id are covered by
    -- chk_approval_requests_type below, and MySQL disallows CASCADE
    -- referential actions on columns used in a CHECK constraint. Both PKs
    -- are AUTO_INCREMENT and are never updated in practice.
    CONSTRAINT fk_approval_requests_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_approval_requests_club
        FOREIGN KEY (club_id) REFERENCES clubs(club_id)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT chk_approval_requests_type CHECK (
        (request_type = 'company' AND company_id IS NOT NULL AND club_id IS NULL)
        OR
        (request_type = 'club' AND club_id IS NOT NULL AND company_id IS NULL)
    ),
    KEY idx_approval_requests_status (status),
    KEY idx_approval_requests_type (request_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================================
-- ============================================================================
-- Screen-backed collaboration, engagement, career and administration features
-- ============================================================================
-- student_courses now records repeat enrollments by academic semester.
-- Keep jobs.required_skills as display text; job_skills drives skill filtering.
-- Empty job_universities/job_departments sets mean unrestricted targeting.
-- NULL announcement target_department means all students in that university.
-- Derive review averages, RSVPs, unread totals and rolling analytics from rows.
-- Increment resources.download_count atomically with resource_activity inserts.
-- Reserve circle/event seats in transactions while locking the parent row.
-- Backend must validate conversation membership for send/read/invite operations,
-- and allow direct messaging only between active, verified, accepted partners.
-- Message storage alone does not provide the UI's claimed end-to-end encryption;
-- a client key-management/encryption protocol is required before that claim is true.
-- Audit entity references intentionally survive subject removal; avoid secrets
-- in details. Session tokens are random secrets; store only their SHA-256 hashes.

CREATE TABLE saved_resources (
    user_id BIGINT UNSIGNED NOT NULL,
    resource_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, resource_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE resource_reviews (
    resource_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    rating TINYINT UNSIGNED NOT NULL,
    review_text TEXT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_resource_rating CHECK (rating BETWEEN 1 AND 5),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (resource_id, user_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE tags (
    tag_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE resource_tags (
    resource_id BIGINT UNSIGNED NOT NULL,
    tag_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (resource_id, tag_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (tag_id) REFERENCES tags(tag_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE resource_activity (
    activity_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    resource_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NULL,
    action ENUM('view','download') NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    KEY idx_resource_activity_trending (action, created_at, resource_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE resource_moderation (
    moderation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    resource_id BIGINT UNSIGNED NOT NULL,
    reviewed_by BIGINT UNSIGNED NULL,
    decision ENUM('flagged','approved','rejected','removed') NOT NULL,
    reason TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (reviewed_by) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE study_preferences (
    user_id BIGINT UNSIGNED PRIMARY KEY,
    current_course_id BIGINT UNSIGNED NULL,
    milestone ENUM('midterm','final_exam','lab_assignment','other') NULL,
    study_goal TEXT NULL,
    availability VARCHAR(500) NULL,
    preferred_location VARCHAR(200) NULL,
    study_mode ENUM('in_person','online','either') NOT NULL DEFAULT 'either',
    discoverable TINYINT(1) NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES student_profiles(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (current_course_id) REFERENCES courses(course_id) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE study_circles (
    circle_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id BIGINT UNSIGNED NOT NULL,
    created_by BIGINT UNSIGNED NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    location VARCHAR(200) NULL,
    meeting_url VARCHAR(500) NULL,
    starts_at DATETIME NOT NULL,
    ends_at DATETIME NULL,
    capacity SMALLINT UNSIGNED NOT NULL,
    status ENUM('open','closed','completed','cancelled') NOT NULL DEFAULT 'open',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_circle_capacity CHECK (capacity > 0),
    CONSTRAINT chk_circle_times CHECK (ends_at IS NULL OR ends_at > starts_at),
    FOREIGN KEY (course_id) REFERENCES courses(course_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE study_circle_members (
    circle_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    role ENUM('member','organizer') NOT NULL DEFAULT 'member',
    status ENUM('invited','joined','declined','left') NOT NULL DEFAULT 'joined',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (circle_id, user_id),
    FOREIGN KEY (circle_id) REFERENCES study_circles(circle_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE direct_conversations (
    conversation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_one_id BIGINT UNSIGNED NOT NULL,
    user_two_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_conversation_order CHECK (user_one_id < user_two_id),
    UNIQUE KEY uq_conversation_pair (user_one_id, user_two_id),
    FOREIGN KEY (user_one_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_two_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE study_session_invites (
    invite_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    conversation_id BIGINT UNSIGNED NOT NULL,
    invited_by BIGINT UNSIGNED NOT NULL,
    course_id BIGINT UNSIGNED NOT NULL,
    location VARCHAR(200) NOT NULL,
    starts_at DATETIME NOT NULL,
    proposed_starts_at DATETIME NULL,
    status ENUM('pending','accepted','declined','reschedule_requested','cancelled') NOT NULL DEFAULT 'pending',
    responded_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (conversation_id) REFERENCES direct_conversations(conversation_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (invited_by) REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (course_id) REFERENCES courses(course_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE direct_messages (
    message_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    conversation_id BIGINT UNSIGNED NOT NULL,
    sender_id BIGINT UNSIGNED NOT NULL,
    body TEXT NULL,
    resource_id BIGINT UNSIGNED NULL,
    invite_id BIGINT UNSIGNED NULL,
    attachment_url VARCHAR(500) NULL,
    attachment_name VARCHAR(255) NULL,
    delivered_at DATETIME NULL,
    read_at DATETIME NULL,
    edited_at DATETIME NULL,
    deleted_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (conversation_id) REFERENCES direct_conversations(conversation_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    FOREIGN KEY (invite_id) REFERENCES study_session_invites(invite_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    KEY idx_messages_conversation (conversation_id, created_at, message_id),
    KEY idx_messages_unread (conversation_id, read_at, sender_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE club_followers (
    club_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (club_id, user_id),
    FOREIGN KEY (club_id) REFERENCES clubs(club_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE event_rsvps (
    event_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    status ENUM('registered','waitlisted','cancelled','attended') NOT NULL DEFAULT 'registered',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id, user_id),
    FOREIGN KEY (event_id) REFERENCES club_events(event_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE saved_events (
    user_id BIGINT UNSIGNED NOT NULL,
    event_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, event_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (event_id) REFERENCES club_events(event_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE club_gallery (
    image_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id BIGINT UNSIGNED NOT NULL,
    image_url VARCHAR(500) NOT NULL,
    title VARCHAR(150) NULL,
    caption VARCHAR(500) NULL,
    academic_term VARCHAR(30) NULL,
    display_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (club_id) REFERENCES clubs(club_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE club_focus_areas (
    focus_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id BIGINT UNSIGNED NOT NULL,
    title VARCHAR(100) NOT NULL,
    description VARCHAR(500) NULL,
    icon VARCHAR(100) NULL,
    display_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    FOREIGN KEY (club_id) REFERENCES clubs(club_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE club_profile_views (
    view_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (club_id) REFERENCES clubs(club_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    KEY idx_club_views_period (club_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE club_announcement_views (
    announcement_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (announcement_id, user_id),
    FOREIGN KEY (announcement_id) REFERENCES club_announcements(announcement_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE job_skills (
    job_id BIGINT UNSIGNED NOT NULL,
    skill_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (job_id, skill_id),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (skill_id) REFERENCES skills(skill_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE job_universities (
    job_id BIGINT UNSIGNED NOT NULL,
    university_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (job_id, university_id),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (university_id) REFERENCES universities(university_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE job_departments (
    job_id BIGINT UNSIGNED NOT NULL,
    department VARCHAR(100) NOT NULL,
    PRIMARY KEY (job_id, department),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE company_universities (
    company_id BIGINT UNSIGNED NOT NULL,
    university_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (company_id, university_id),
    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (university_id) REFERENCES universities(university_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE job_views (
    view_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    job_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    KEY idx_job_views_period (job_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE badges (
    badge_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(500) NULL,
    icon_url VARCHAR(500) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE student_badges (
    user_id BIGINT UNSIGNED NOT NULL,
    badge_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, badge_id),
    FOREIGN KEY (user_id) REFERENCES student_profiles(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (badge_id) REFERENCES badges(badge_id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reputation_events (
    reputation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    points INT NOT NULL,
    reason VARCHAR(200) NOT NULL,
    resource_id BIGINT UNSIGNED NULL,
    idempotency_key VARCHAR(190) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE notifications (
    notification_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NULL,
    target_path VARCHAR(500) NULL,
    read_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    KEY idx_notifications_inbox (user_id, read_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE audit_logs (
    audit_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    actor_id BIGINT UNSIGNED NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id BIGINT UNSIGNED NULL,
    details JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_id) REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE RESTRICT,
    KEY idx_audit_created (created_at),
    KEY idx_audit_entity (entity_type, entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_sessions (
    session_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE RESTRICT,
    KEY idx_sessions_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- SEED / DEMO DATA
-- All password_hash / otp_hash values below are clearly-marked fake
-- placeholders. Replace them with real bcrypt/Argon2 hashes generated by
-- the application before using this data outside of a demo environment.
-- ============================================================================

-- ---- University --------------------------------------------------------
INSERT INTO universities (name, email_domain, location, status) VALUES
('North South University', 'northsouth.edu', 'Dhaka, Bangladesh', 'active');

-- ---- Users (3 students, 1 university admin, 1 recruiter, 1 super admin) --
INSERT INTO users (full_name, email, password_hash, account_type, account_status, email_verified) VALUES
('Rahim Ahmed',      'rahim.ahmed@northsouth.edu',        'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_1', 'student',          'active', 1),
('Anika Tabassum',   'anika.tabassum@northsouth.edu',     'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_2', 'student',          'active', 1),
('Tanvir Hasan',     'tanvir.hasan@northsouth.edu',       'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_3', 'student',          'active', 1),
('Dr. Farzana Karim','farzana.karim@northsouth.edu',      'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_4', 'university_admin', 'active', 1),
('Samia Reza',       'samia.reza@brainstation23.com',     'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_5', 'recruiter',        'active', 1),
('Super Admin',      'superadmin@unilink.io',             'FAKE_DEMO_HASH_REPLACE_WITH_BCRYPT_OR_ARGON2_6', 'super_admin',      'active', 1);

-- ---- Student profiles ----------------------------------------------------
INSERT INTO student_profiles (user_id, university_id, student_id, department, semester)
SELECT u.user_id, uni.university_id, '2021-1-60-101', 'Computer Science', '7th'
FROM users u JOIN universities uni ON uni.name = 'North South University'
WHERE u.email = 'rahim.ahmed@northsouth.edu';

INSERT INTO student_profiles (user_id, university_id, student_id, department, semester)
SELECT u.user_id, uni.university_id, '2021-1-60-102', 'Computer Science', '7th'
FROM users u JOIN universities uni ON uni.name = 'North South University'
WHERE u.email = 'anika.tabassum@northsouth.edu';

INSERT INTO student_profiles (user_id, university_id, student_id, department, semester)
SELECT u.user_id, uni.university_id, '2020-2-60-045', 'Economics', '9th'
FROM users u JOIN universities uni ON uni.name = 'North South University'
WHERE u.email = 'tanvir.hasan@northsouth.edu';

-- ---- University admin link ------------------------------------------------
INSERT INTO university_admins (user_id, university_id)
SELECT u.user_id, uni.university_id
FROM users u JOIN universities uni ON uni.name = 'North South University'
WHERE u.email = 'farzana.karim@northsouth.edu';

-- ---- Courses ---------------------------------------------------------------
INSERT INTO courses (university_id, course_code, course_name, department)
SELECT university_id, 'CSE311', 'Database Management Systems', 'Computer Science'
FROM universities WHERE name = 'North South University';

INSERT INTO courses (university_id, course_code, course_name, department)
SELECT university_id, 'CSE327', 'Software Engineering', 'Computer Science'
FROM universities WHERE name = 'North South University';

INSERT INTO courses (university_id, course_code, course_name, department)
SELECT university_id, 'MAT120', 'Calculus I', 'Mathematics'
FROM universities WHERE name = 'North South University';

-- ---- Student <-> Course enrollments (for study-partner matching) ----------
INSERT INTO student_courses (user_id, course_id, academic_semester)
SELECT u.user_id, c.course_id, 'Fall 2026'
FROM users u, courses c
WHERE u.email = 'rahim.ahmed@northsouth.edu' AND c.course_code = 'CSE311';

INSERT INTO student_courses (user_id, course_id, academic_semester)
SELECT u.user_id, c.course_id, 'Fall 2026'
FROM users u, courses c
WHERE u.email = 'anika.tabassum@northsouth.edu' AND c.course_code = 'CSE311';

INSERT INTO student_courses (user_id, course_id, academic_semester)
SELECT u.user_id, c.course_id, 'Fall 2026'
FROM users u, courses c
WHERE u.email = 'anika.tabassum@northsouth.edu' AND c.course_code = 'MAT120';

INSERT INTO student_courses (user_id, course_id, academic_semester)
SELECT u.user_id, c.course_id, 'Fall 2026'
FROM users u, courses c
WHERE u.email = 'tanvir.hasan@northsouth.edu' AND c.course_code = 'CSE327';

-- ---- Resources (3 demo uploads) --------------------------------------------
INSERT INTO resources (uploaded_by, course_id, title, resource_type, academic_semester, file_url, original_file_name, mime_type, file_size, download_count, status)
SELECT u.user_id, c.course_id,
       'Relational Algebra & SQL Query Guide', 'notes', 'Fall 2026',
       'https://cdn.unilink.edu/resources/cse311-relational-algebra.pdf',
       'cse311-relational-algebra.pdf', 'application/pdf', 2148213, 184, 'active'
FROM users u, courses c
WHERE u.email = 'rahim.ahmed@northsouth.edu' AND c.course_code = 'CSE311';

INSERT INTO resources (uploaded_by, course_id, title, resource_type, academic_semester, file_url, original_file_name, mime_type, file_size, download_count, status)
SELECT u.user_id, c.course_id,
       'Integration Techniques & Taylor Series Cheat Sheet', 'question_bank', 'Fall 2026',
       'https://cdn.unilink.edu/resources/mat120-integration-cheatsheet.pdf',
       'mat120-integration-cheatsheet.pdf', 'application/pdf', 981344, 340, 'active'
FROM users u, courses c
WHERE u.email = 'anika.tabassum@northsouth.edu' AND c.course_code = 'MAT120';

INSERT INTO resources (uploaded_by, course_id, title, resource_type, academic_semester, file_url, original_file_name, mime_type, file_size, download_count, status)
SELECT u.user_id, c.course_id,
       'Software Engineering — Midterm Slide Deck', 'slides', 'Fall 2026',
       'https://cdn.unilink.edu/resources/cse327-midterm-slides.pdf',
       'cse327-midterm-slides.pdf', 'application/pdf', 3540211, 88, 'active'
FROM users u, courses c
WHERE u.email = 'tanvir.hasan@northsouth.edu' AND c.course_code = 'CSE327';

-- ---- Skills -----------------------------------------------------------------
INSERT INTO skills (skill_name) VALUES
('Python'), ('Java'), ('SQL'), ('UI/UX'), ('Research'), ('Presentation');

INSERT INTO student_skills (user_id, skill_id)
SELECT u.user_id, s.skill_id FROM users u, skills s
WHERE u.email = 'rahim.ahmed@northsouth.edu' AND s.skill_name IN ('SQL','Python');

INSERT INTO student_skills (user_id, skill_id)
SELECT u.user_id, s.skill_id FROM users u, skills s
WHERE u.email = 'anika.tabassum@northsouth.edu' AND s.skill_name IN ('Research','Presentation');

INSERT INTO student_skills (user_id, skill_id)
SELECT u.user_id, s.skill_id FROM users u, skills s
WHERE u.email = 'tanvir.hasan@northsouth.edu' AND s.skill_name IN ('Java','UI/UX');

-- ---- Club, membership, event, announcement -----------------------------------
INSERT INTO clubs (university_id, club_name, category, tagline, description, meeting_location, founded_year, status)
SELECT university_id, 'NSU Robotics Club', 'Technology',
       'Building the future, one robot at a time',
       'A student-run club focused on autonomous systems, robotics competitions, and hands-on workshops.',
       'SAC Lab 402', 2018, 'active'
FROM universities WHERE name = 'North South University';

INSERT INTO club_memberships (club_id, user_id, role, status)
SELECT c.club_id, u.user_id, 'admin', 'active'
FROM clubs c, users u
WHERE c.club_name = 'NSU Robotics Club' AND u.email = 'rahim.ahmed@northsouth.edu';

INSERT INTO club_memberships (club_id, user_id, role, status)
SELECT c.club_id, u.user_id, 'member', 'active'
FROM clubs c, users u
WHERE c.club_name = 'NSU Robotics Club' AND u.email = 'anika.tabassum@northsouth.edu';

INSERT INTO club_events (club_id, created_by, title, description, event_date, start_time, location, status)
SELECT c.club_id, u.user_id,
       'NSU Robotics Club — Autonomous Rover Workshop',
       'Hands-on workshop building and programming autonomous rovers. Open to all skill levels.',
       '2026-11-14', '15:30:00', 'SAC Lab 402', 'published'
FROM clubs c, users u
WHERE c.club_name = 'NSU Robotics Club' AND u.email = 'rahim.ahmed@northsouth.edu';

INSERT INTO club_announcements (club_id, created_by, title, content, pinned, status)
SELECT c.club_id, u.user_id,
       'Welcome to Fall 2026!',
       'Kickoff meeting this Friday at 4 PM in SAC Lab 402. New members welcome — no experience required.',
       1, 'published'
FROM clubs c, users u
WHERE c.club_name = 'NSU Robotics Club' AND u.email = 'rahim.ahmed@northsouth.edu';

-- ---- Company, recruiter, job --------------------------------------------------
INSERT INTO companies (company_name, website, industry, location, description, status) VALUES
('Brain Station 23', 'https://brainstation23.com', 'Software & IT Services',
 'Gulshan, Dhaka', 'A leading software engineering company delivering products for global clients.', 'active');

INSERT INTO company_recruiters (company_id, user_id)
SELECT co.company_id, u.user_id
FROM companies co, users u
WHERE co.company_name = 'Brain Station 23' AND u.email = 'samia.reza@brainstation23.com';

INSERT INTO jobs (company_id, posted_by, title, job_type, location, description, required_skills, application_deadline, status)
SELECT co.company_id, u.user_id,
       'Software Engineering Intern', 'internship', 'Gulshan, Dhaka',
       'Work with our engineering team on production web applications built with React and Node.js. Great mentorship and a path to full-time conversion.',
       'React, Node.js, SQL', '2026-12-15', 'active'
FROM companies co, users u
WHERE co.company_name = 'Brain Station 23' AND u.email = 'samia.reza@brainstation23.com';

-- A demo application from a student
INSERT INTO applications (job_id, student_id, status)
SELECT j.job_id, u.user_id, 'submitted'
FROM jobs j, users u
WHERE j.title = 'Software Engineering Intern' AND u.email = 'rahim.ahmed@northsouth.edu';

-- ---- University announcement ----------------------------------------------
INSERT INTO university_announcements (university_id, created_by, title, content, important, status)
SELECT uni.university_id, u.user_id,
       'Fall 2026 Registration Deadline',
       'All students must complete course registration by October 5, 2026. Late registration will incur a fee.',
       1, 'published'
FROM universities uni, users u
WHERE uni.name = 'North South University' AND u.email = 'farzana.karim@northsouth.edu';

-- ---- Approval request history (demonstrates the approval workflow) --------
INSERT INTO approval_requests (request_type, requested_by, company_id, status, reviewed_by, requested_at, reviewed_at)
SELECT 'company', u2.user_id, co.company_id, 'approved', u1.user_id, '2026-08-01 10:00:00', '2026-08-02 09:00:00'
FROM companies co, users u1, users u2
WHERE co.company_name = 'Brain Station 23'
  AND u1.email = 'superadmin@unilink.io'
  AND u2.email = 'samia.reza@brainstation23.com';

INSERT INTO approval_requests (request_type, requested_by, club_id, status, reviewed_by, requested_at, reviewed_at)
SELECT 'club', u2.user_id, c.club_id, 'approved', u1.user_id, '2026-07-10 12:00:00', '2026-07-11 08:30:00'
FROM clubs c, users u1, users u2
WHERE c.club_name = 'NSU Robotics Club'
  AND u1.email = 'superadmin@unilink.io'
  AND u2.email = 'rahim.ahmed@northsouth.edu';


-- ============================================================================
-- SAMPLE QUERIES
-- ============================================================================

-- 1. Login lookup — find user by email
-- SELECT user_id, full_name, email, password_hash, account_type, account_status, email_verified
-- FROM users
-- WHERE email = 'rahim.ahmed@northsouth.edu';

-- 2. Student resource search — by course_code and resource_type
-- SELECT r.resource_id, r.title, r.resource_type, r.file_url, r.download_count
-- FROM resources r
-- JOIN courses c ON c.course_id = r.course_id
-- WHERE c.course_code = 'CSE311'
--   AND r.resource_type = 'notes'
--   AND r.status = 'active';

-- 3. Study partner search — other students taking the same course as a given user
-- SELECT DISTINCT u.user_id, u.full_name, c.course_code
-- FROM student_courses sc1
-- JOIN student_courses sc2
--   ON sc2.course_id = sc1.course_id AND sc2.user_id <> sc1.user_id
-- JOIN users u ON u.user_id = sc2.user_id
-- JOIN courses c ON c.course_id = sc1.course_id
-- WHERE sc1.user_id = 1;  -- replace 1 with the target student's user_id

-- 4. Club admin verification — does this student administer this club?
-- SELECT EXISTS (
--     SELECT 1 FROM club_memberships
--     WHERE club_id = 1 AND user_id = 1 AND role = 'admin' AND status = 'active'
-- ) AS is_club_admin;

-- 5. Recruiter jobs — all jobs posted by one company
-- SELECT j.job_id, j.title, j.job_type, j.status, j.application_deadline
-- FROM jobs j
-- JOIN companies co ON co.company_id = j.company_id
-- WHERE co.company_name = 'Brain Station 23';

-- 6. Job applications — count applications for a job
-- SELECT job_id, COUNT(*) AS total_applications
-- FROM applications
-- WHERE job_id = 1
-- GROUP BY job_id;

-- 7. University students — verified students belonging to one university
-- SELECT u.user_id, u.full_name, sp.student_id, sp.department, sp.semester
-- FROM users u
-- JOIN student_profiles sp ON sp.user_id = u.user_id
-- JOIN universities uni ON uni.university_id = sp.university_id
-- WHERE uni.name = 'North South University'
--   AND u.email_verified = 1;

-- 8. Pending approvals — everything the super admin still needs to review
-- SELECT approval_id, request_type, company_id, club_id, requested_by, requested_at
-- FROM approval_requests
-- WHERE status = 'pending';

-- 9. Super Admin statistics
-- SELECT COUNT(*) AS total_students FROM users WHERE account_type = 'student';
-- SELECT COUNT(*) AS total_clubs FROM clubs WHERE status = 'active';
-- SELECT COUNT(*) AS total_companies FROM companies WHERE status = 'active';
-- SELECT COUNT(*) AS total_universities FROM universities WHERE status = 'active';
-- SELECT COUNT(*) AS active_jobs FROM jobs WHERE status = 'active';
-- SELECT COUNT(*) AS shared_resources FROM resources WHERE status = 'active';

-- 10. Campus Feed — combine recent resources, announcements, events, and jobs
-- SELECT 'resource' AS content_type, resource_id AS content_id, title,
--        (SELECT full_name FROM users WHERE user_id = resources.uploaded_by) AS source_name,
--        created_at
-- FROM resources
-- WHERE status = 'active'
-- UNION ALL
-- SELECT 'university_announcement', announcement_id, title,
--        (SELECT name FROM universities WHERE university_id = university_announcements.university_id),
--        created_at
-- FROM university_announcements
-- WHERE status = 'published'
-- UNION ALL
-- SELECT 'club_event', event_id, title,
--        (SELECT club_name FROM clubs WHERE club_id = club_events.club_id),
--        created_at
-- FROM club_events
-- WHERE status = 'published'
-- UNION ALL
-- SELECT 'club_announcement', announcement_id, title,
--        (SELECT club_name FROM clubs WHERE club_id = club_announcements.club_id),
--        created_at
-- FROM club_announcements
-- WHERE status = 'published'
-- UNION ALL
-- SELECT 'job', job_id, title,
--        (SELECT company_name FROM companies WHERE company_id = jobs.company_id),
--        created_at
-- FROM jobs
-- WHERE status = 'active'
-- ORDER BY created_at DESC;
