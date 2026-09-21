<?php
declare(strict_types=1);

// Lightweight persistent backend for classroom/MVP use when PDO MySQL is not
// available. Data is locked and stored outside the public web root.
ini_set('display_errors','0');
ini_set('log_errors','1');
$storageRoot = dirname(__DIR__,2) . '/storage';
$dataDir = $storageRoot . '/data';
$uploadDir = $storageRoot . '/uploads';
if (!is_dir($dataDir)) mkdir($dataDir,0750,true);
if (!is_dir($uploadDir)) mkdir($uploadDir,0750,true);
$dataFile = $dataDir . '/unilink.json';

$secureCookie = !empty($_SERVER['HTTPS']) || strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_set_cookie_params(['httponly'=>true,'secure'=>$secureCookie,'samesite'=>'Lax','path'=>'/']);
    session_start();
}

function f_json(mixed $data,int $status=200): never { http_response_code($status); header('Content-Type: application/json; charset=utf-8'); echo json_encode($data,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES); exit; }
function f_body(): array {
    $type=strtolower((string)($_SERVER['CONTENT_TYPE']??''));
    if (str_contains($type,'application/json')) {
        $raw=file_get_contents('php://input'); $d=json_decode((string)$raw,true); return is_array($d)?$d:[];
    }
    return $_POST;
}
function f_empty_store(): array {
    return ['counters'=>['user'=>0,'post'=>0,'request'=>0,'conversation'=>0,'message'=>0,'resource'=>0,'notification'=>0],
        'users'=>[],'profiles'=>[],'posts'=>[],'requests'=>[],'conversations'=>[],'messages'=>[],'resources'=>[],'notifications'=>[]];
}
function f_normalize_store(array $d): array {
    $base=f_empty_store();
    foreach ($base as $k=>$v) if (!array_key_exists($k,$d) || !is_array($d[$k])) $d[$k]=$v;
    foreach ($base['counters'] as $k=>$v) if (!isset($d['counters'][$k])) $d['counters'][$k]=0;
    return $d;
}
function f_read_store(): array {
    global $dataFile;
    $h=fopen($dataFile,'c+'); if(!$h) throw new RuntimeException('Storage unavailable');
    flock($h,LOCK_SH); rewind($h); $raw=stream_get_contents($h); flock($h,LOCK_UN); fclose($h);
    $d=$raw?json_decode($raw,true):null; return f_normalize_store(is_array($d)?$d:[]);
}
function f_mutate(callable $fn): mixed {
    global $dataFile;
    $h=fopen($dataFile,'c+'); if(!$h) throw new RuntimeException('Storage unavailable');
    if(!flock($h,LOCK_EX)){fclose($h);throw new RuntimeException('Storage lock unavailable');}
    rewind($h); $raw=stream_get_contents($h); $decoded=$raw?json_decode($raw,true):null; $d=f_normalize_store(is_array($decoded)?$decoded:[]);
    try { $result=$fn($d); rewind($h); ftruncate($h,0); fwrite($h,json_encode($d,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT)); fflush($h); }
    finally { flock($h,LOCK_UN); fclose($h); }
    return $result;
}
function f_next(array &$d,string $counter): int { return ++$d['counters'][$counter]; }
function f_now(): string { return gmdate('Y-m-d H:i:s'); }
function f_user_from(array $d,?int $id=null): ?array {
    $id=$id??(int)($_SESSION['user_id']??0); if($id<1)return null;
    foreach($d['users'] as $u) if((int)$u['user_id']===$id && ($u['account_status']??'')==='active') return $u;
    return null;
}
function f_require_user(?array $d=null): array { $d=$d??f_read_store(); $u=f_user_from($d); if(!$u)f_json(['error'=>'Authentication required'],401); unset($u['password_hash']); return $u; }
function f_find_user(array $d,int $id): ?array { foreach($d['users'] as $u) if((int)$u['user_id']===$id)return $u; return null; }
function f_notify(array &$d,int $userId,string $type,string $title,?string $body=null,?string $target=null): void {
    $d['notifications'][]=['notification_id'=>f_next($d,'notification'),'user_id'=>$userId,'notification_type'=>$type,'title'=>$title,'body'=>$body,'target_path'=>$target,'read_at'=>null,'created_at'=>f_now()];
}
function f_profile(array $d,int $uid): ?array { foreach($d['profiles'] as $p) if((int)$p['user_id']===$uid)return $p; return null; }
function f_safe_name(string $name): string { $name=preg_replace('/[^A-Za-z0-9._ -]/u','_',basename($name)); return $name?:'download'; }

set_exception_handler(function(Throwable $e){ error_log((string)$e); f_json(['error'=>'Unable to complete this request. Please try again.'],500); });

$method=$_SERVER['REQUEST_METHOD']??'GET';

if ($path==='/api/health' && $method==='GET') {
    $d=f_read_store(); f_json(['ok'=>true,'database'=>'file','users'=>count($d['users']),'time'=>gmdate('c')]);
}

if ($path==='/api/auth/register' && $method==='POST') {
    $b=f_body();
    foreach(['full_name','email','password','student_id','department'] as $k) if(trim((string)($b[$k]??''))==='') f_json(['error'=>"$k is required"],422);
    $name=trim((string)$b['full_name']); $email=strtolower(trim((string)$b['email'])); $password=(string)$b['password'];
    $studentId=trim((string)$b['student_id']); $department=trim((string)$b['department']); $university=trim((string)($b['university_name']??'North South University'));
    if(!filter_var($email,FILTER_VALIDATE_EMAIL))f_json(['error'=>'Enter a valid email address'],422);
    if(strlen($password)<8)f_json(['error'=>'Password must be at least 8 characters'],422);
    $uid=f_mutate(function(&$d)use($name,$email,$password,$studentId,$department,$university,$b){
        foreach($d['users'] as $u) if(strtolower($u['email'])===$email) f_json(['error'=>'That email is already registered'],409);
        foreach($d['profiles'] as $p) if(strcasecmp((string)$p['university_name'],$university)===0 && strcasecmp((string)$p['student_id'],$studentId)===0) f_json(['error'=>'That student ID is already registered'],409);
        $uid=f_next($d,'user'); $now=f_now();
        $d['users'][]=['user_id'=>$uid,'full_name'=>$name,'email'=>$email,'password_hash'=>password_hash($password,PASSWORD_DEFAULT),'account_type'=>'student','account_status'=>'active','email_verified'=>0,'last_seen_at'=>null,'created_at'=>$now,'updated_at'=>$now];
        $d['profiles'][]=['user_id'=>$uid,'university_name'=>$university,'student_id'=>$studentId,'department'=>$department,'semester'=>trim((string)($b['semester']??''))?:null,'location'=>null,'github_url'=>null,'linkedin_url'=>null,'portfolio_url'=>null,'bio'=>null,'created_at'=>$now,'updated_at'=>$now];
        return $uid;
    });
    f_json(['message'=>'Registration successful','user_id'=>$uid],201);
}

if ($path==='/api/auth/login' && $method==='POST') {
    $b=f_body(); $email=strtolower(trim((string)($b['email']??''))); $password=(string)($b['password']??'');
    $d=f_read_store(); $found=null; foreach($d['users'] as $u) if(strtolower($u['email'])===$email){$found=$u;break;}
    if(!$found || !password_verify($password,$found['password_hash']) || $found['account_status']!=='active')f_json(['error'=>'Invalid email or password'],401);
    session_regenerate_id(true); $_SESSION['user_id']=(int)$found['user_id'];
    f_mutate(function(&$d)use($found){foreach($d['users'] as &$u)if((int)$u['user_id']===(int)$found['user_id']){$u['last_seen_at']=f_now();break;}unset($u);});
    unset($found['password_hash']); f_json(['user'=>$found]);
}

if ($path==='/api/auth/logout' && $method==='POST') {
    $_SESSION=[]; $params=session_get_cookie_params();
    setcookie(session_name(),'', ['expires'=>time()-3600,'path'=>$params['path']?:'/','domain'=>$params['domain']?:'','secure'=>(bool)$params['secure'],'httponly'=>true,'samesite'=>'Lax']);
    session_destroy(); f_json(['message'=>'Logged out']);
}
if ($path==='/api/auth/me' && $method==='GET') { $u=f_require_user(); f_json(['user'=>$u]); }

if ($path==='/api/profile' && $method==='GET') {
    $d=f_read_store(); $u=f_require_user($d); $p=f_profile($d,(int)$u['user_id'])??[]; f_json(['profile'=>array_merge($u,$p)]);
}
if ($path==='/api/profile' && in_array($method,['PUT','PATCH'],true)) {
    $u=f_require_user(); $b=f_body(); $allowed=['bio','location','github_url','linkedin_url','portfolio_url','semester','department']; $changed=false;
    f_mutate(function(&$d)use($u,$b,$allowed,&$changed){foreach($d['profiles'] as &$p){if((int)$p['user_id']!==(int)$u['user_id'])continue;foreach($allowed as $k)if(array_key_exists($k,$b)){$p[$k]=trim((string)$b[$k])?:null;$changed=true;}$p['updated_at']=f_now();break;}unset($p);});
    if(!$changed)f_json(['error'=>'No editable fields supplied'],422); f_json(['message'=>'Profile updated']);
}

if ($path==='/api/posts' && $method==='GET') {
    $d=f_read_store(); f_require_user($d); $items=$d['posts']; usort($items,fn($a,$b)=>($b['post_id']<=>$a['post_id']));
    foreach($items as &$p){$u=f_find_user($d,(int)$p['author_id']);$p['author_name']=$u['full_name']??'Student';}unset($p); f_json(['items'=>array_slice($items,0,100)]);
}
if ($path==='/api/posts' && $method==='POST') {
    $u=f_require_user(); $b=f_body(); $content=trim((string)($b['content']??'')); if($content==='')f_json(['error'=>'Post cannot be empty'],422); if(strlen($content)>5000)f_json(['error'=>'Post is too long'],422);
    $id=f_mutate(function(&$d)use($u,$content){$id=f_next($d,'post');$d['posts'][]=['post_id'=>$id,'author_id'=>(int)$u['user_id'],'content'=>$content,'created_at'=>f_now(),'updated_at'=>f_now()];return $id;}); f_json(['post_id'=>$id],201);
}

if ($path==='/api/users/search' && $method==='GET') {
    $d=f_read_store(); $me=f_require_user($d); $q=strtolower(trim((string)($_GET['q']??''))); $items=[];
    foreach($d['users'] as $u){if((int)$u['user_id']===(int)$me['user_id']||$u['account_status']!=='active'||$u['account_type']!=='student')continue;$p=f_profile($d,(int)$u['user_id'])??[];$hay=strtolower(($u['full_name']??'').' '.($p['student_id']??'').' '.($p['department']??''));if($q===''||str_contains($hay,$q))$items[]=['user_id'=>$u['user_id'],'full_name'=>$u['full_name'],'student_id'=>$p['student_id']??null,'department'=>$p['department']??null,'semester'=>$p['semester']??null,'bio'=>$p['bio']??null];}
    usort($items,fn($a,$b)=>strcasecmp($a['full_name'],$b['full_name'])); f_json(['items'=>array_slice($items,0,50)]);
}

if ($path==='/api/connections/request' && $method==='POST') {
    $me=f_require_user(); $b=f_body(); $to=(int)($b['user_id']??$b['receiver_id']??0); if($to<1||$to===(int)$me['user_id'])f_json(['error'=>'Invalid connection target'],422);
    $id=f_mutate(function(&$d)use($me,$to,$b){$target=f_find_user($d,$to);if(!$target||$target['account_status']!=='active')f_json(['error'=>'Student not found'],404);foreach($d['requests'] as $r){$same=((int)$r['sender_id']===(int)$me['user_id']&&(int)$r['receiver_id']===$to)||((int)$r['sender_id']===$to&&(int)$r['receiver_id']===(int)$me['user_id']);if($same&&$r['status']==='accepted')f_json(['error'=>'You are already connected'],409);if($same&&$r['status']==='pending')f_json(['error'=>'A connection request is already pending'],409);} $id=f_next($d,'request');$d['requests'][]=['request_id'=>$id,'sender_id'=>(int)$me['user_id'],'receiver_id'=>$to,'message'=>trim((string)($b['message']??''))?:null,'status'=>'pending','created_at'=>f_now(),'updated_at'=>f_now()];f_notify($d,$to,'connection_request','New study partner request',$me['full_name'].' wants to connect with you.','/unilink-study-partners.html');return $id;}); f_json(['request_id'=>$id],201);
}
if ($path==='/api/connections/requests' && $method==='GET') {
    $d=f_read_store();$me=f_require_user($d);$items=[];foreach($d['requests'] as $r)if((int)$r['receiver_id']===(int)$me['user_id']&&$r['status']==='pending'){$u=f_find_user($d,(int)$r['sender_id']);$r['sender_name']=$u['full_name']??'Student';$items[]=$r;}usort($items,fn($a,$b)=>$b['request_id']<=>$a['request_id']);f_json(['items'=>$items]);
}
if (preg_match('#^/api/connections/(\d+)$#',$path,$m)&&$method==='PATCH') {
    $me=f_require_user();$b=f_body();$status=in_array($b['status']??'', ['accepted','declined'],true)?$b['status']:'';if(!$status)f_json(['error'=>'Invalid status'],422);$rid=(int)$m[1];$updated=f_mutate(function(&$d)use($me,$status,$rid){foreach($d['requests'] as &$r){if((int)$r['request_id']===$rid&&(int)$r['receiver_id']===(int)$me['user_id']&&$r['status']==='pending'){$r['status']=$status;$r['updated_at']=f_now();if($status==='accepted')f_notify($d,(int)$r['sender_id'],'connection_accepted','Study partner request accepted',$me['full_name'].' accepted your request.','/unilink-study-partners.html');unset($r);return 1;}}unset($r);return 0;});if(!$updated)f_json(['error'=>'Request not found'],404);f_json(['updated'=>1]);
}
if ($path==='/api/connections' && $method==='GET') {
    $d=f_read_store();$me=f_require_user($d);$items=[];foreach($d['requests'] as $r){if($r['status']!=='accepted')continue;$other=0;if((int)$r['sender_id']===(int)$me['user_id'])$other=(int)$r['receiver_id'];elseif((int)$r['receiver_id']===(int)$me['user_id'])$other=(int)$r['sender_id'];if($other){$u=f_find_user($d,$other);if($u)$items[]=['request_id'=>$r['request_id'],'user_id'=>$other,'full_name'=>$u['full_name'],'status'=>'accepted'];}}f_json(['items'=>$items]);
}

if ($path==='/api/conversations' && $method==='GET') {
    $d=f_read_store();$me=f_require_user($d);$items=[];foreach($d['conversations'] as $c){$other=0;if((int)$c['user_one_id']===(int)$me['user_id'])$other=(int)$c['user_two_id'];elseif((int)$c['user_two_id']===(int)$me['user_id'])$other=(int)$c['user_one_id'];if($other){$u=f_find_user($d,$other);$items[]=['conversation_id'=>$c['conversation_id'],'created_at'=>$c['created_at'],'participant_id'=>$other,'participant_name'=>$u['full_name']??'Student'];}}usort($items,fn($a,$b)=>$b['conversation_id']<=>$a['conversation_id']);f_json(['items'=>$items]);
}
if ($path==='/api/conversations' && $method==='POST') {
    $me=f_require_user();$b=f_body();$other=(int)($b['user_id']??0);if($other<1||$other===(int)$me['user_id'])f_json(['error'=>'Invalid participant'],422);$id=f_mutate(function(&$d)use($me,$other){$target=f_find_user($d,$other);if(!$target||$target['account_status']!=='active')f_json(['error'=>'User not found'],404);$a=min((int)$me['user_id'],$other);$z=max((int)$me['user_id'],$other);foreach($d['conversations'] as $c)if((int)$c['user_one_id']===$a&&(int)$c['user_two_id']===$z)return (int)$c['conversation_id'];$id=f_next($d,'conversation');$d['conversations'][]=['conversation_id'=>$id,'user_one_id'=>$a,'user_two_id'=>$z,'created_at'=>f_now()];return $id;});f_json(['conversation_id'=>$id],201);
}
if (preg_match('#^/api/conversations/(\d+)/messages$#',$path,$m)&&$method==='GET') {
    $d=f_read_store();$me=f_require_user($d);$cid=(int)$m[1];$conv=null;foreach($d['conversations'] as $c)if((int)$c['conversation_id']===$cid&&((int)$c['user_one_id']===(int)$me['user_id']||(int)$c['user_two_id']===(int)$me['user_id'])){$conv=$c;break;}if(!$conv)f_json(['error'=>'Conversation not found'],404);$items=[];foreach($d['messages'] as $msg)if((int)$msg['conversation_id']===$cid){$u=f_find_user($d,(int)$msg['sender_id']);$msg['sender_name']=$u['full_name']??'Student';$items[]=$msg;}usort($items,fn($a,$b)=>$a['message_id']<=>$b['message_id']);f_mutate(function(&$d)use($cid,$me){foreach($d['messages'] as &$msg)if((int)$msg['conversation_id']===$cid&&(int)$msg['sender_id']!==(int)$me['user_id']&&empty($msg['read_at']))$msg['read_at']=f_now();unset($msg);});f_json(['items'=>$items]);
}
if (preg_match('#^/api/conversations/(\d+)/messages$#',$path,$m)&&$method==='POST') {
    $me=f_require_user();$b=f_body();$cid=(int)$m[1];$text=trim((string)($b['body']??''));if($text==='')f_json(['error'=>'Message is required'],422);if(strlen($text)>10000)f_json(['error'=>'Message is too long'],422);$id=f_mutate(function(&$d)use($me,$cid,$text){$conv=null;foreach($d['conversations'] as $c)if((int)$c['conversation_id']===$cid&&((int)$c['user_one_id']===(int)$me['user_id']||(int)$c['user_two_id']===(int)$me['user_id'])){$conv=$c;break;}if(!$conv)f_json(['error'=>'Conversation not found'],404);$id=f_next($d,'message');$d['messages'][]=['message_id'=>$id,'conversation_id'=>$cid,'sender_id'=>(int)$me['user_id'],'body'=>$text,'delivered_at'=>f_now(),'read_at'=>null,'created_at'=>f_now()];$recipient=((int)$conv['user_one_id']===(int)$me['user_id'])?(int)$conv['user_two_id']:(int)$conv['user_one_id'];f_notify($d,$recipient,'message','New message from '.$me['full_name'],substr($text,0,160),'/unilink_direct_messaging.html?conversation='.$cid);return $id;});f_json(['message_id'=>$id],201);
}

if ($path==='/api/resources' && $method==='GET') {
    $d=f_read_store();f_require_user($d);$q=strtolower(trim((string)($_GET['q']??'')));$items=[];foreach($d['resources'] as $r){if(($r['status']??'')!=='active')continue;$u=f_find_user($d,(int)$r['uploaded_by']);$r['uploader']=$u['full_name']??'Student';$r['course_code']='GENERAL';$r['course_name']='General Shared Resources';$hay=strtolower(($r['title']??'').' '.($r['uploader']??''));if($q===''||str_contains($hay,$q))$items[]=$r;}usort($items,fn($a,$b)=>$b['resource_id']<=>$a['resource_id']);f_json(['items'=>$items]);
}
if ($path==='/api/resources' && $method==='POST') {
    global $uploadDir;
    $me=f_require_user();if(!isset($_FILES['file']))f_json(['error'=>'Choose a file to upload'],422);$f=$_FILES['file'];if(($f['error']??UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK)f_json(['error'=>'The upload failed'],422);if(($f['size']??0)<1||$f['size']>25*1024*1024)f_json(['error'=>'File must be 25 MB or smaller'],422);$title=trim((string)($_POST['title']??''));if($title==='')f_json(['error'=>'Resource title is required'],422);$ext=strtolower(pathinfo((string)$f['name'],PATHINFO_EXTENSION));if(!in_array($ext,['pdf','docx','pptx'],true))f_json(['error'=>'Only PDF, DOCX and PPTX files are allowed'],422);if(!is_uploaded_file($f['tmp_name']))f_json(['error'=>'Invalid upload'],422);$mime='application/octet-stream';if(class_exists('finfo')){$fi=new finfo(FILEINFO_MIME_TYPE);$mime=(string)$fi->file($f['tmp_name']);if($ext==='pdf'&&$mime!=='application/pdf')f_json(['error'=>'The selected file is not a valid PDF'],422);}elseif($ext==='pdf'){$head=file_get_contents($f['tmp_name'],false,null,0,5);if($head!=='%PDF-')f_json(['error'=>'The selected file is not a valid PDF'],422);} $stored=bin2hex(random_bytes(16)).'.'.$ext;$dest=$uploadDir.DIRECTORY_SEPARATOR.$stored;if(!move_uploaded_file($f['tmp_name'],$dest))f_json(['error'=>'Server could not save the file'],500);try{$id=f_mutate(function(&$d)use($me,$title,$f,$stored,$mime){$id=f_next($d,'resource');$d['resources'][]=['resource_id'=>$id,'uploaded_by'=>(int)$me['user_id'],'title'=>$title,'resource_type'=>'notes','description'=>trim((string)($_POST['description']??''))?:null,'file_url'=>$stored,'original_file_name'=>$f['name'],'mime_type'=>$mime,'file_size'=>(int)$f['size'],'download_count'=>0,'status'=>'active','created_at'=>f_now(),'updated_at'=>f_now()];return $id;});f_json(['message'=>'Resource uploaded','resource_id'=>$id],201);}catch(Throwable $e){@unlink($dest);throw $e;}
}
if (preg_match('#^/api/resources/(\d+)/download$#',$path,$m)&&$method==='GET') {
    global $uploadDir;
    $d=f_read_store();f_require_user($d);$rid=(int)$m[1];$r=null;foreach($d['resources'] as $x)if((int)$x['resource_id']===$rid&&$x['status']==='active'){$r=$x;break;}if(!$r)f_json(['error'=>'Resource not found'],404);$base=realpath($uploadDir);$file=$base?realpath($base.DIRECTORY_SEPARATOR.basename((string)$r['file_url'])):false;if(!$file||!$base||!str_starts_with($file,$base.DIRECTORY_SEPARATOR)||!is_file($file))f_json(['error'=>'File unavailable'],404);f_mutate(function(&$d)use($rid){foreach($d['resources'] as &$x)if((int)$x['resource_id']===$rid){$x['download_count']=(int)($x['download_count']??0)+1;break;}unset($x);});header('Content-Type: '.($r['mime_type']?:'application/octet-stream'));header('Content-Length: '.filesize($file));header('Content-Disposition: attachment; filename="'.str_replace('"','',f_safe_name((string)($r['original_file_name']??'download'))).'"');readfile($file);exit;
}

if ($path==='/api/notifications' && $method==='GET') {$d=f_read_store();$me=f_require_user($d);$items=array_values(array_filter($d['notifications'],fn($n)=>(int)$n['user_id']===(int)$me['user_id']));usort($items,fn($a,$b)=>$b['notification_id']<=>$a['notification_id']);f_json(['items'=>array_slice($items,0,100)]);}
if (preg_match('#^/api/notifications/(\d+)/read$#',$path,$m)&&$method==='PATCH'){$me=f_require_user();$nid=(int)$m[1];$updated=f_mutate(function(&$d)use($me,$nid){foreach($d['notifications'] as &$n)if((int)$n['notification_id']===$nid&&(int)$n['user_id']===(int)$me['user_id']){$n['read_at']=f_now();unset($n);return 1;}unset($n);return 0;});f_json(['updated'=>$updated]);}

f_json(['error'=>'Route not found'],404);
