-- UniLink core MVP schema for real-user testing.
-- MySQL 8+/MariaDB 10.5+. Safe for a fresh database.
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS universities (
  university_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(150) NOT NULL UNIQUE,
  email_domain VARCHAR(100) NULL UNIQUE,
  location VARCHAR(150) NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_sessions (
  session_id VARCHAR(128) PRIMARY KEY,
  session_data MEDIUMBLOB NOT NULL,
  last_activity INT UNSIGNED NOT NULL,
  KEY idx_mvp_sessions_activity (last_activity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
  user_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  account_type ENUM('student','recruiter','university_admin','super_admin') NOT NULL DEFAULT 'student',
  account_status ENUM('pending_verification','pending_approval','active','suspended','rejected') NOT NULL DEFAULT 'active',
  email_verified TINYINT(1) NOT NULL DEFAULT 0,
  avatar_url VARCHAR(500) NULL,
  last_seen_at DATETIME NULL,
  terms_accepted_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_users_status (account_status),
  KEY idx_users_type (account_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS student_profiles (
  user_id BIGINT UNSIGNED PRIMARY KEY,
  university_id BIGINT UNSIGNED NOT NULL,
  student_id VARCHAR(50) NOT NULL,
  department VARCHAR(100) NOT NULL,
  semester VARCHAR(20) NULL,
  location VARCHAR(150) NULL,
  github_url VARCHAR(500) NULL,
  linkedin_url VARCHAR(500) NULL,
  portfolio_url VARCHAR(500) NULL,
  bio TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_profile_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_mvp_profile_university FOREIGN KEY (university_id) REFERENCES universities(university_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_mvp_student_id (university_id, student_id),
  KEY idx_mvp_profile_university (university_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS posts (
  post_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  author_id BIGINT UNSIGNED NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_post_author FOREIGN KEY (author_id) REFERENCES users(user_id) ON DELETE CASCADE,
  KEY idx_mvp_posts_created (created_at),
  KEY idx_mvp_posts_author (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS courses (
  course_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  university_id BIGINT UNSIGNED NOT NULL,
  course_code VARCHAR(20) NOT NULL,
  course_name VARCHAR(150) NOT NULL,
  department VARCHAR(100) NOT NULL DEFAULT 'General',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_course_university FOREIGN KEY (university_id) REFERENCES universities(university_id) ON DELETE CASCADE,
  UNIQUE KEY uq_mvp_course_code (university_id, course_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS resources (
  resource_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uploaded_by BIGINT UNSIGNED NOT NULL,
  course_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(200) NOT NULL,
  resource_type ENUM('notes','past_exam','assignment','slides','question_bank','lab_report','formula_sheet','other') NOT NULL DEFAULT 'notes',
  description TEXT NULL,
  file_url VARCHAR(500) NOT NULL,
  original_file_name VARCHAR(255) NULL,
  mime_type VARCHAR(100) NULL,
  file_size BIGINT UNSIGNED NULL,
  file_data MEDIUMBLOB NULL,
  download_count INT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('draft','pending_review','active','rejected','removed') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_resource_user FOREIGN KEY (uploaded_by) REFERENCES users(user_id) ON DELETE RESTRICT,
  CONSTRAINT fk_mvp_resource_course FOREIGN KEY (course_id) REFERENCES courses(course_id) ON DELETE RESTRICT,
  KEY idx_mvp_resource_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS study_partner_requests (
  request_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  sender_id BIGINT UNSIGNED NOT NULL,
  receiver_id BIGINT UNSIGNED NOT NULL,
  message VARCHAR(500) NULL,
  status ENUM('pending','accepted','declined','cancelled') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_request_sender FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_mvp_request_receiver FOREIGN KEY (receiver_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT chk_mvp_not_self CHECK (sender_id <> receiver_id),
  KEY idx_mvp_requests_receiver (receiver_id, status),
  KEY idx_mvp_requests_sender (sender_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS direct_conversations (
  conversation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_one_id BIGINT UNSIGNED NOT NULL,
  user_two_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_conv_one FOREIGN KEY (user_one_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_mvp_conv_two FOREIGN KEY (user_two_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT chk_mvp_conv_order CHECK (user_one_id < user_two_id),
  UNIQUE KEY uq_mvp_conversation_pair (user_one_id, user_two_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS direct_messages (
  message_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  conversation_id BIGINT UNSIGNED NOT NULL,
  sender_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  delivered_at DATETIME NULL,
  read_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_message_conversation FOREIGN KEY (conversation_id) REFERENCES direct_conversations(conversation_id) ON DELETE CASCADE,
  CONSTRAINT fk_mvp_message_sender FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE CASCADE,
  KEY idx_mvp_messages_conversation (conversation_id, created_at, message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notifications (
  notification_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  notification_type VARCHAR(50) NOT NULL,
  title VARCHAR(200) NOT NULL,
  body TEXT NULL,
  target_path VARCHAR(500) NULL,
  read_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_notification_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  KEY idx_mvp_notifications (user_id, read_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_logs (
  audit_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  actor_id BIGINT UNSIGNED NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id BIGINT UNSIGNED NULL,
  details JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mvp_audit_user FOREIGN KEY (actor_id) REFERENCES users(user_id) ON DELETE SET NULL,
  KEY idx_mvp_audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO universities (name,email_domain,location,status) VALUES
('North South University','northsouth.edu','Dhaka, Bangladesh','active'),
('University of Dhaka','du.ac.bd','Dhaka, Bangladesh','active'),
('BRAC University','bracu.ac.bd','Dhaka, Bangladesh','active')
ON DUPLICATE KEY UPDATE status=VALUES(status), location=VALUES(location);

INSERT INTO courses (university_id,course_code,course_name,department)
SELECT university_id,'GENERAL','General Shared Resources','General' FROM universities
ON DUPLICATE KEY UPDATE course_name=VALUES(course_name);
