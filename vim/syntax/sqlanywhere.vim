
" Vim syntax file
" Language:    SQL, Adaptive Server Anywhere
" Maintainer:  David Fishburn <fishburn at ianywhere dot com>
" Last Change: 2009 Mar 15
" Version:     11.0.1

" Description: Updated to Adaptive Server Anywhere 11.0.1
"              Updated to Adaptive Server Anywhere 10.0.1
"              Updated to Adaptive Server Anywhere  9.0.2
"              Updated to Adaptive Server Anywhere  9.0.1
"              Updated to Adaptive Server Anywhere  9.0.0
"
" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
    syntax clear
elseif exists("b:current_syntax")
    finish
endif

syn case ignore

" The SQL reserved words, defined as keywords.

syn keyword sqlSpecial  false null true

" common functions
syn keyword sqlFunction	 count sum avg min max debug_eng isnull
syn keyword sqlFunction	 greater lesser argn string ymd todate
syn keyword sqlFunction	 totimestamp date today now utc_now
syn keyword sqlFunction	 number identity years months weeks days
syn keyword sqlFunction	 hours minutes seconds second minute hour
syn keyword sqlFunction	 day month year dow date_format substr
syn keyword sqlFunction	 substring byte_substr length byte_length
syn keyword sqlFunction	 datalength ifnull evaluate list
syn keyword sqlFunction	 soundex similar difference like_start
syn keyword sqlFunction	 like_end regexp_compile
syn keyword sqlFunction	 regexp_compile_patindex remainder abs
syn keyword sqlFunction	 graphical_plan plan explanation ulplan
syn keyword sqlFunction	 graphical_ulplan long_ulplan
syn keyword sqlFunction	 short_ulplan rewrite watcomsql
syn keyword sqlFunction	 transactsql dialect estimate
syn keyword sqlFunction	 estimate_source index_estimate
syn keyword sqlFunction	 experience_estimate traceback wsql_state
syn keyword sqlFunction	 lang_message dateadd datediff datepart
syn keyword sqlFunction	 datename dayname monthname quarter
syn keyword sqlFunction	 tsequal hextoint inttohex rand textptr
syn keyword sqlFunction	 rowid grouping stddev variance rank
syn keyword sqlFunction	 dense_rank density percent_rank user_name
syn keyword sqlFunction	 user_id str stuff char_length nullif
syn keyword sqlFunction	 sortkey compare ts_index_statistics
syn keyword sqlFunction	 ts_table_statistics isdate isnumeric
syn keyword sqlFunction	 get_identity lookup newid uuidtostr
syn keyword sqlFunction	 strtouuid varexists

" 9.0.1 functions
syn keyword sqlFunction	 acos asin atan atn2 cast ceiling convert cos cot
syn keyword sqlFunction	 char_length coalesce dateformat datetime degrees exp
syn keyword sqlFunction	 floor getdate insertstr
syn keyword sqlFunction	 log log10 lower mod pi power
syn keyword sqlFunction	 property radians replicate round sign sin
syn keyword sqlFunction	 sqldialect tan truncate truncnum
syn keyword sqlFunction	 base64_encode base64_decode
syn keyword sqlFunction	 hash compress decompress encrypt decrypt

" 11.0.1 functions
syn keyword sqlFunction	 connection_extended_property text_handle_vector_match
syn keyword sqlFunction	 read_client_file write_client_file

" string functions
syn keyword sqlFunction	 ascii char left ltrim repeat
syn keyword sqlFunction	 space right rtrim trim lcase ucase
syn keyword sqlFunction	 locate charindex patindex replace
syn keyword sqlFunction	 errormsg csconvert

" property functions
syn keyword sqlFunction	 db_id db_name property_name
syn keyword sqlFunction	 property_description property_number
syn keyword sqlFunction	 next_connection next_database property
syn keyword sqlFunction	 connection_property db_property db_extended_property
syn keyword sqlFunction	 event_parmeter event_condition event_condition_name

" sa_ procedures
syn keyword sqlFunction	 sa_add_index_consultant_analysis
syn keyword sqlFunction	 sa_add_workload_query
syn keyword sqlFunction  sa_app_deregister
syn keyword sqlFunction  sa_app_get_infoStr
syn keyword sqlFunction  sa_app_get_status
syn keyword sqlFunction  sa_app_register
syn keyword sqlFunction  sa_app_registration_unlock
syn keyword sqlFunction  sa_app_set_infoStr
syn keyword sqlFunction  sa_audit_string
syn keyword sqlFunction  sa_check_commit
syn keyword sqlFunction  sa_checkpoint_execute
syn keyword sqlFunction  sa_conn_activity
syn keyword sqlFunction  sa_conn_compression_info
syn keyword sqlFunction  sa_conn_deregister
syn keyword sqlFunction  sa_conn_info
syn keyword sqlFunction  sa_conn_properties
syn keyword sqlFunction  sa_conn_properties_by_conn
syn keyword sqlFunction  sa_conn_properties_by_name
syn keyword sqlFunction  sa_conn_register
syn keyword sqlFunction  sa_conn_set_status
syn keyword sqlFunction  sa_create_analysis_from_query
syn keyword sqlFunction  sa_db_info
syn keyword sqlFunction  sa_db_properties
syn keyword sqlFunction  sa_disable_auditing_type
syn keyword sqlFunction  sa_disable_index
syn keyword sqlFunction  sa_disk_free_space
syn keyword sqlFunction  sa_enable_auditing_type
syn keyword sqlFunction  sa_enable_index
syn keyword sqlFunction  sa_end_forward_to
syn keyword sqlFunction  sa_eng_properties
syn keyword sqlFunction  sa_event_schedules
syn keyword sqlFunction  sa_exec_script
syn keyword sqlFunction  sa_flush_cache
syn keyword sqlFunction  sa_flush_statistics
syn keyword sqlFunction  sa_forward_to
syn keyword sqlFunction  sa_get_dtt
syn keyword sqlFunction  sa_get_histogram
syn keyword sqlFunction  sa_get_request_profile
syn keyword sqlFunction  sa_get_request_profile_sub
syn keyword sqlFunction  sa_get_request_times
syn keyword sqlFunction  sa_get_server_messages
syn keyword sqlFunction  sa_get_simulated_scale_factors
syn keyword sqlFunction  sa_get_workload_capture_status
syn keyword sqlFunction  sa_index_density
syn keyword sqlFunction  sa_index_levels
syn keyword sqlFunction  sa_index_statistics
syn keyword sqlFunction  sa_internal_alter_index_ability
syn keyword sqlFunction  sa_internal_create_analysis_from_query
syn keyword sqlFunction  sa_internal_disk_free_space
syn keyword sqlFunction  sa_internal_get_dtt
syn keyword sqlFunction  sa_internal_get_histogram
syn keyword sqlFunction  sa_internal_get_request_times
syn keyword sqlFunction  sa_internal_get_simulated_scale_factors
syn keyword sqlFunction  sa_internal_get_workload_capture_status
syn keyword sqlFunction  sa_internal_index_density
syn keyword sqlFunction  sa_internal_index_levels
syn keyword sqlFunction  sa_internal_index_statistics
syn keyword sqlFunction  sa_internal_java_loaded_classes
syn keyword sqlFunction  sa_internal_locks
syn keyword sqlFunction  sa_internal_pause_workload_capture
syn keyword sqlFunction  sa_internal_procedure_profile
syn keyword sqlFunction  sa_internal_procedure_profile_summary
syn keyword sqlFunction  sa_internal_read_backup_history
syn keyword sqlFunction  sa_internal_recommend_indexes
syn keyword sqlFunction  sa_internal_reset_identity
syn keyword sqlFunction  sa_internal_resume_workload_capture
syn keyword sqlFunction  sa_internal_start_workload_capture
syn keyword sqlFunction  sa_internal_stop_index_consultant
syn keyword sqlFunction  sa_internal_stop_workload_capture
syn keyword sqlFunction  sa_internal_table_fragmentation
syn keyword sqlFunction  sa_internal_table_page_usage
syn keyword sqlFunction  sa_internal_table_stats
syn keyword sqlFunction  sa_internal_virtual_sysindex
syn keyword sqlFunction  sa_internal_virtual_sysixcol
syn keyword sqlFunction  sa_java_loaded_classes
syn keyword sqlFunction  sa_jdk_version
syn keyword sqlFunction  sa_locks
syn keyword sqlFunction  sa_make_object
syn keyword sqlFunction  sa_pause_workload_capture
syn keyword sqlFunction  sa_proc_debug_attach_to_connection
syn keyword sqlFunction  sa_proc_debug_connect
syn keyword sqlFunction  sa_proc_debug_detach_from_connection
syn keyword sqlFunction  sa_proc_debug_disconnect
syn keyword sqlFunction  sa_proc_debug_get_connection_name
syn keyword sqlFunction  sa_proc_debug_release_connection
syn keyword sqlFunction  sa_proc_debug_request
syn keyword sqlFunction  sa_proc_debug_version
syn keyword sqlFunction  sa_proc_debug_wait_for_connection
syn keyword sqlFunction  sa_procedure_profile
syn keyword sqlFunction  sa_procedure_profile_summary
syn keyword sqlFunction  sa_read_backup_history
syn keyword sqlFunction  sa_recommend_indexes
syn keyword sqlFunction  sa_recompile_views
syn keyword sqlFunction  sa_remove_index_consultant_analysis
syn keyword sqlFunction  sa_remove_index_consultant_workload
syn keyword sqlFunction  sa_reset_identity
syn keyword sqlFunction  sa_resume_workload_capture
syn keyword sqlFunction  sa_server_option
syn keyword sqlFunction  sa_set_simulated_scale_factor
syn keyword sqlFunction  sa_setremoteuser
syn keyword sqlFunction  sa_setsubscription
syn keyword sqlFunction  sa_start_recording_commits
syn keyword sqlFunction  sa_start_workload_capture
syn keyword sqlFunction  sa_statement_text
syn keyword sqlFunction  sa_stop_index_consultant
syn keyword sqlFunction  sa_stop_recording_commits
syn keyword sqlFunction  sa_stop_workload_capture
syn keyword sqlFunction  sa_sync
syn keyword sqlFunction  sa_sync_sub
syn keyword sqlFunction  sa_table_fragmentation
syn keyword sqlFunction  sa_table_page_usage
syn keyword sqlFunction  sa_table_stats
syn keyword sqlFunction  sa_update_index_consultant_workload
syn keyword sqlFunction  sa_validate
syn keyword sqlFunction  sa_virtual_sysindex
syn keyword sqlFunction  sa_virtual_sysixcol

" sp_ procedures
syn keyword sqlFunction  sp_addalias
syn keyword sqlFunction  sp_addauditrecord
syn keyword sqlFunction  sp_adddumpdevice
syn keyword sqlFunction  sp_addgroup
syn keyword sqlFunction  sp_addlanguage
syn keyword sqlFunction  sp_addlogin
syn keyword sqlFunction  sp_addmessage
syn keyword sqlFunction  sp_addremotelogin
syn keyword sqlFunction  sp_addsegment
syn keyword sqlFunction  sp_addserver
syn keyword sqlFunction  sp_addthreshold
syn keyword sqlFunction  sp_addtype
syn keyword sqlFunction  sp_adduser
syn keyword sqlFunction  sp_auditdatabase
syn keyword sqlFunction  sp_auditlogin
syn keyword sqlFunction  sp_auditobject
syn keyword sqlFunction  sp_auditoption
syn keyword sqlFunction  sp_auditsproc
syn keyword sqlFunction  sp_bindefault
syn keyword sqlFunction  sp_bindmsg
syn keyword sqlFunction  sp_bindrule
syn keyword sqlFunction  sp_changedbowner
syn keyword sqlFunction  sp_changegroup
syn keyword sqlFunction  sp_checknames
syn keyword sqlFunction  sp_checkperms
syn keyword sqlFunction  sp_checkreswords
syn keyword sqlFunction  sp_clearstats
syn keyword sqlFunction  sp_column_privileges
syn keyword sqlFunction  sp_columns
syn keyword sqlFunction  sp_commonkey
syn keyword sqlFunction  sp_configure
syn keyword sqlFunction  sp_cursorinfo
syn keyword sqlFunction  sp_databases
syn keyword sqlFunction  sp_datatype_info
syn keyword sqlFunction  sp_dboption
syn keyword sqlFunction  sp_dbremap
syn keyword sqlFunction  sp_depends
syn keyword sqlFunction  sp_diskdefault
syn keyword sqlFunction  sp_displaylogin
syn keyword sqlFunction  sp_dropalias
syn keyword sqlFunction  sp_dropdevice
syn keyword sqlFunction  sp_dropgroup
syn keyword sqlFunction  sp_dropkey
syn keyword sqlFunction  sp_droplanguage
syn keyword sqlFunction  sp_droplogin
syn keyword sqlFunction  sp_dropmessage
syn keyword sqlFunction  sp_dropremotelogin
syn keyword sqlFunction  sp_dropsegment
syn keyword sqlFunction  sp_dropserver
syn keyword sqlFunction  sp_dropthreshold
syn keyword sqlFunction  sp_droptype
syn keyword sqlFunction  sp_dropuser
syn keyword sqlFunction  sp_estspace
syn keyword sqlFunction  sp_extendsegment
syn keyword sqlFunction  sp_fkeys
syn keyword sqlFunction  sp_foreignkey
syn keyword sqlFunction  sp_getmessage
syn keyword sqlFunction  sp_help
syn keyword sqlFunction  sp_helpconstraint
syn keyword sqlFunction  sp_helpdb
syn keyword sqlFunction  sp_helpdevice
syn keyword sqlFunction  sp_helpgroup
syn keyword sqlFunction  sp_helpindex
syn keyword sqlFunction  sp_helpjoins
syn keyword sqlFunction  sp_helpkey
syn keyword sqlFunction  sp_helplanguage
syn keyword sqlFunction  sp_helplog
syn keyword sqlFunction  sp_helpprotect
syn keyword sqlFunction  sp_helpremotelogin
syn keyword sqlFunction  sp_helpsegment
syn keyword sqlFunction  sp_helpserver
syn keyword sqlFunction  sp_helpsort
syn keyword sqlFunction  sp_helptext
syn keyword sqlFunction  sp_helpthreshold
syn keyword sqlFunction  sp_helpuser
syn keyword sqlFunction  sp_indsuspect
syn keyword sqlFunction  sp_lock
syn keyword sqlFunction  sp_locklogin
syn keyword sqlFunction  sp_logdevice
syn keyword sqlFunction  sp_login_environment
syn keyword sqlFunction  sp_modifylogin
syn keyword sqlFunction  sp_modifythreshold
syn keyword sqlFunction  sp_monitor
syn keyword sqlFunction  sp_password
syn keyword sqlFunction  sp_pkeys
syn keyword sqlFunction  sp_placeobject
syn keyword sqlFunction  sp_primarykey
syn keyword sqlFunction  sp_procxmode
syn keyword sqlFunction  sp_recompile
syn keyword sqlFunction  sp_remap
syn keyword sqlFunction  sp_remote_columns
syn keyword sqlFunction  sp_remote_exported_keys
syn keyword sqlFunction  sp_remote_imported_keys
syn keyword sqlFunction  sp_remote_pcols
syn keyword sqlFunction  sp_remote_primary_keys
syn keyword sqlFunction  sp_remote_procedures
syn keyword sqlFunction  sp_remote_tables
syn keyword sqlFunction  sp_remoteoption
syn keyword sqlFunction  sp_rename
syn keyword sqlFunction  sp_renamedb
syn keyword sqlFunction  sp_reportstats
syn keyword sqlFunction  sp_reset_tsql_environment
syn keyword sqlFunction  sp_role
syn keyword sqlFunction  sp_server_info
syn keyword sqlFunction  sp_servercaps
syn keyword sqlFunction  sp_serverinfo
syn keyword sqlFunction  sp_serveroption
syn keyword sqlFunction  sp_setlangalias
syn keyword sqlFunction  sp_setreplicate
syn keyword sqlFunction  sp_setrepproc
syn keyword sqlFunction  sp_setreptable
syn keyword sqlFunction  sp_spaceused
syn keyword sqlFunction  sp_special_columns
syn keyword sqlFunction  sp_sproc_columns
syn keyword sqlFunction  sp_statistics
syn keyword sqlFunction  sp_stored_procedures
syn keyword sqlFunction  sp_syntax
syn keyword sqlFunction  sp_table_privileges
syn keyword sqlFunction  sp_tables
syn keyword sqlFunction  sp_tsql_environment
syn keyword sqlFunction  sp_tsql_feature_not_supported
syn keyword sqlFunction  sp_unbindefault
syn keyword sqlFunction  sp_unbindmsg
syn keyword sqlFunction  sp_unbindrule
syn keyword sqlFunction  sp_volchanged
syn keyword sqlFunction  sp_who
syn keyword sqlFunction  xp_scanf
syn keyword sqlFunction  xp_sprintf

" server functions
syn keyword sqlFunction  col_length
syn keyword sqlFunction  col_name
syn keyword sqlFunction  index_col
syn keyword sqlFunction  object_id
syn keyword sqlFunction  object_name
syn keyword sqlFunction  proc_role
syn keyword sqlFunction  show_role
syn keyword sqlFunction  xp_cmdshell
syn keyword sqlFunction  xp_msver
syn keyword sqlFunction  xp_read_file
syn keyword sqlFunction  xp_real_cmdshell
syn keyword sqlFunction  xp_real_read_file
syn keyword sqlFunction  xp_real_sendmail
syn keyword sqlFunction  xp_real_startmail
syn keyword sqlFunction  xp_real_startsmtp
syn keyword sqlFunction  xp_real_stopmail
syn keyword sqlFunction  xp_real_stopsmtp
syn keyword sqlFunction  xp_real_write_file
syn keyword sqlFunction  xp_scanf
syn keyword sqlFunction  xp_sendmail
syn keyword sqlFunction  xp_sprintf
syn keyword sqlFunction  xp_startmail
syn keyword sqlFunction  xp_startsmtp
syn keyword sqlFunction  xp_stopmail
syn keyword sqlFunction  xp_stopsmtp
syn keyword sqlFunction  xp_write_file

" http functions
syn keyword sqlFunction	 http_header http_variable
syn keyword sqlFunction	 next_http_header next_http_variable
syn keyword sqlFunction	 sa_set_http_header sa_set_http_option
syn keyword sqlFunction	 sa_http_variable_info sa_http_header_info

" http functions 9.0.1
syn keyword sqlFunction	 http_encode http_decode
syn keyword sqlFunction	 html_encode html_decode

" keywords
syn keyword sqlKeyword	 absolute accent action active add address aes_decrypt
syn keyword sqlKeyword	 after aggregate algorithm allow_dup_row allowed
syn keyword sqlKeyword	 alter and ansi_substring any as append apply asc ascii ase
syn keyword sqlKeyword	 assign at atan2 atomic attach attended audit authorization
syn keyword sqlKeyword	 autoincrement autostop batch bcp before
syn keyword sqlKeyword	 between bit_and bit_length bit_or bit_substr bit_xor
syn keyword sqlKeyword	 blank blanks block
syn keyword sqlKeyword	 both bottom unbounded break breaker bufferpool
syn keyword sqlKeyword	 build bulk by byte bytes cache calibrate calibration
syn keyword sqlKeyword	 cancel capability cascade cast
syn keyword sqlKeyword	 catalog ceil changes char char_convert check checksum
syn keyword sqlKeyword	 class classes client cmp
syn keyword sqlKeyword	 cluster clustered collation
syn keyword sqlKeyword	 column columns
syn keyword sqlKeyword	 command comment committed comparisons
syn keyword sqlKeyword	 compatible component compressed compute computes
syn keyword sqlKeyword	 concat configuration confirm conflict connection
syn keyword sqlKeyword	 console consolidate consolidated
syn keyword sqlKeyword	 constraint constraints content continue
syn keyword sqlKeyword	 convert coordinator copy count count_set_bits
syn keyword sqlKeyword	 crc createtime cross cube cume_dist
syn keyword sqlKeyword	 current cursor data data database
syn keyword sqlKeyword	 current_timestamp current_user
syn keyword sqlKeyword	 databases datatype dba dbfile
syn keyword sqlKeyword	 dbspace dbspaces dbspacename debug decoupled
syn keyword sqlKeyword	 decrypted default defaults default_dbspace deferred
syn keyword sqlKeyword	 definer definition
syn keyword sqlKeyword	 delay deleting delimited dependencies desc
syn keyword sqlKeyword	 description detach deterministic directory
syn keyword sqlKeyword	 disable disabled distinct do domain download duplicate
syn keyword sqlKeyword	 dsetpass dttm dynamic each editproc ejb
syn keyword sqlKeyword	 else elseif empty enable encapsulated encrypted end
syn keyword sqlKeyword	 encoding endif engine environment erase error escape escapes event
syn keyword sqlKeyword	 event_parameter every except exception exclude excluded exclusive exec
syn keyword sqlKeyword	 existing exists expanded expiry express exprtype extended_property
syn keyword sqlKeyword	 external externlogin factor failover false
syn keyword sqlKeyword	 fastfirstrow fieldproc file files filler
syn keyword sqlKeyword	 fillfactor finish first first_keyword first_value
syn keyword sqlKeyword	 following force foreign format forxml forxml_sep fp frame
syn keyword sqlKeyword	 freepage french fresh full function gb get_bit go global
syn keyword sqlKeyword	 group handler hash having header hexadecimal
syn keyword sqlKeyword	 hidden high history hg hng hold holdlock host
syn keyword sqlKeyword	 hours http_body http_session_timeout id identified identity ignore
syn keyword sqlKeyword	 ignore_dup_key ignore_dup_row immediate
syn keyword sqlKeyword	 in inactiv inactive inactivity included incremental
syn keyword sqlKeyword	 index index_enabled index_lparen indexonly info
syn keyword sqlKeyword	 inline inner inout insensitive inserting
syn keyword sqlKeyword	 instead integrated
syn keyword sqlKeyword	 internal intersection into introduced invoker iq is isolation
syn keyword sqlKeyword	 jar java java_location java_main_userid java_vm_options
syn keyword sqlKeyword	 jconnect jdk join kb key keep kerberos language last
syn keyword sqlKeyword	 last_keyword last_value lateral ld left len lf ln level like
syn keyword sqlKeyword	 limit local location log
syn keyword sqlKeyword	 logging login logscan long low lru main manual mark
syn keyword sqlKeyword	 match matched materialized max maximum mb membership
syn keyword sqlKeyword	 merge metadata methods minimum minutes mirror mode modify monitor move mru
syn keyword sqlKeyword	 multiplex name named national native natural new next no
syn keyword sqlKeyword	 noholdlock nolock nonclustered none not
syn keyword sqlKeyword	 notify null nullable_constant nulls object oem_string of off offline
syn keyword sqlKeyword	 old on online only openstring optimization optimizer option
syn keyword sqlKeyword	 or order others out outer over
syn keyword sqlKeyword	 package packetsize padding page pages
syn keyword sqlKeyword	 paglock parallel part partial partition partitions partner password path
syn keyword sqlKeyword	 pctfree plan policy populate port postfilter preceding precision
syn keyword sqlKeyword	 prefetch prefilter prefix preserve preview primary
syn keyword sqlKeyword	 prior priority priqty private privileges procedure profile
syn keyword sqlKeyword	 property_is_cumulative property_is_numeric public publication publish publisher
syn keyword sqlKeyword	 quiesce quote quotes range readclientfile readcommitted reader readfile readonly
syn keyword sqlKeyword	 readpast readuncommitted readwrite rebuild
syn keyword sqlKeyword	 received recompile recover recursive references
syn keyword sqlKeyword	 referencing refresh regex regexp regexp_substr relative relocate
syn keyword sqlKeyword	 rename repeatable repeatableread
syn keyword sqlKeyword	 replicate request_timeout required rereceive resend reserve reset
syn keyword sqlKeyword	 resizing resolve resource respect
syn keyword sqlKeyword	 restrict result retain
syn keyword sqlKeyword	 returns reverse right role
syn keyword sqlKeyword	 rollup root row row_number rowlock rows save
syn keyword sqlKeyword	 sa_index_hash sa_internal_fk_verify sa_internal_termbreak
syn keyword sqlKeyword	 sa_order_preserving_hash sa_order_preserving_hash_big sa_order_preserving_hash_prefix
syn keyword sqlKeyword	 schedule schema scope scripted scroll seconds secqty security
syn keyword sqlKeyword	 send sensitive sent serializable
syn keyword sqlKeyword	 server server session set_bit set_bits sets
syn keyword sqlKeyword	 share simple since site size skip
syn keyword sqlKeyword	 snapshot soapheader soap_header split some sorted_data
syn keyword sqlKeyword	 sqlcode sqlid sqlflagger sqlstate sqrt square
syn keyword sqlKeyword	 stacker stale statement statistics status stddev_pop stddev_samp
syn keyword sqlKeyword	 stemmer stogroup stoplist store
syn keyword sqlKeyword	 strip stripesizekb striping subpages subscribe subscription
syn keyword sqlKeyword	 subtransaction suser_id suser_name synchronization
syn keyword sqlKeyword	 syntax_error table tablock
syn keyword sqlKeyword	 tablockx tb temp template temporary term then
syn keyword sqlKeyword	 ties timezone to to_char to_nchar top traced_plan tracing
syn keyword sqlKeyword	 transfer transaction transactional tries true
syn keyword sqlKeyword	 tsequal type tune uncommitted unconditionally
syn keyword sqlKeyword	 unenforced unicode unique union unistr unknown unlimited unload
syn keyword sqlKeyword	 unpartition unquiesce updatetime updating updlock upgrade upload
syn keyword sqlKeyword	 upper use user
syn keyword sqlKeyword	 using utc utilities validproc
syn keyword sqlKeyword	 value values varchar variable
syn keyword sqlKeyword	 varying var_pop var_samp vcat verify versions view virtual wait
syn keyword sqlKeyword	 warning wd web when where window with with_auto
syn keyword sqlKeyword	 with_auto with_cube with_rollup without
syn keyword sqlKeyword	 with_lparen within word work workload write writefile
syn keyword sqlKeyword	 writeclientfile writer writers writeserver xlock zeros
" XML function support
syn keyword sqlFunction	 openxml xmlelement xmlforest xmlgen xmlconcat xmlagg
syn keyword sqlFunction	 xmlattributes
syn keyword sqlKeyword	 raw auto elements explicit
" HTTP support
syn keyword sqlKeyword	 authorization secure url service next_soap_header
" HTTP 9.0.2 new procedure keywords
syn keyword sqlKeyword	 namespace certificate clientport proxy
" OLAP support 9.0.0
syn keyword sqlKeyword	 covar_pop covar_samp corr regr_slope regr_intercept
syn keyword sqlKeyword	 regr_count regr_r2 regr_avgx regr_avgy
syn keyword sqlKeyword	 regr_sxx regr_syy regr_sxy

" Alternate keywords
syn keyword sqlKeyword	 character dec options proc reference
syn keyword sqlKeyword	 subtrans tran syn keyword


syn keyword sqlOperator	 in any some all between exists
syn keyword sqlOperator	 like escape not is and or
syn keyword sqlOperator  intersect minus
syn keyword sqlOperator  prior distinct

syn keyword sqlStatement allocate alter backup begin call case
syn keyword sqlStatement checkpoint clear close commit configure connect
syn keyword sqlStatement create deallocate declare delete describe
syn keyword sqlStatement disconnect drop execute exit explain fetch
syn keyword sqlStatement for forward from get goto grant help if include
syn keyword sqlStatement input insert install leave load lock loop
syn keyword sqlStatement message open output parameter parameters passthrough
syn keyword sqlStatement prepare print put raiserror read readtext release
syn keyword sqlStatement remote remove reorganize resignal restore resume
syn keyword sqlStatement return revoke rollback savepoint select
syn keyword sqlStatement set setuser signal start stop synchronize
syn keyword sqlStatement system trigger truncate unload update
syn keyword sqlStatement validate waitfor whenever while writetext


syn keyword sqlType	 char long varchar text
syn keyword sqlType	 bigint decimal double float int integer numeric
syn keyword sqlType	 smallint tinyint real
syn keyword sqlType	 money smallmoney
syn keyword sqlType	 bit
syn keyword sqlType	 date datetime smalldate time timestamp
syn keyword sqlType	 binary image varbinary uniqueidentifier
syn keyword sqlType	 xml unsigned
" New types 10.0.0
syn keyword sqlType	 varbit nchar nvarchar

syn keyword sqlOption    Allow_nulls_by_default
syn keyword sqlOption    Allow_read_client_file
syn keyword sqlOption    Allow_snapshot_isolation
syn keyword sqlOption    Allow_write_client_file
syn keyword sqlOption    Ansi_blanks
syn keyword sqlOption    Ansi_close_cursors_on_rollback
syn keyword sqlOption    Ansi_permissions
syn keyword sqlOption    Ansi_substring
syn keyword sqlOption    Ansi_update_constraints
syn keyword sqlOption    Ansinull
syn keyword sqlOption    Auditing
syn keyword sqlOption    Auditing_options
syn keyword sqlOption    Background_priority
syn keyword sqlOption    Blocking
syn keyword sqlOption    Blocking_timeout
syn keyword sqlOption    Chained
syn keyword sqlOption    Checkpoint_time
syn keyword sqlOption    Cis_option
syn keyword sqlOption    Cis_rowset_size
syn keyword sqlOption    Close_on_endtrans
syn keyword sqlOption    Collect_statistics_on_dml_updates
syn keyword sqlOption    Conn_auditing
syn keyword sqlOption    Connection_authentication
syn keyword sqlOption    Continue_after_raiserror
syn keyword sqlOption    Conversion_error
syn keyword sqlOption    Cooperative_commit_timeout
syn keyword sqlOption    Cooperative_commits
syn keyword sqlOption    Database_authentication
syn keyword sqlOption    Date_format
syn keyword sqlOption    Date_order
syn keyword sqlOption    Debug_messages
syn keyword sqlOption    Dedicated_task
syn keyword sqlOption    Default_dbspace
syn keyword sqlOption    Default_timestamp_increment
syn keyword sqlOption    Delayed_commit_timeout
syn keyword sqlOption    Delayed_commits
syn keyword sqlOption    Escape_character
syn keyword sqlOption    Exclude_operators
syn keyword sqlOption    Extended_join_syntax
syn keyword sqlOption    Fire_triggers
syn keyword sqlOption    First_day_of_week
syn keyword sqlOption    For_xml_null_treatment
syn keyword sqlOption    Force_view_creation
syn keyword sqlOption    Global_database_id
syn keyword sqlOption    Http_session_timeout
syn keyword sqlOption    Integrated_server_name
syn keyword sqlOption    Isolation_level
syn keyword sqlOption    Java_location
syn keyword sqlOption    Java_main_userid
syn keyword sqlOption    Java_vm_options
syn keyword sqlOption    Lock_rejected_rows
syn keyword sqlOption    Log_deadlocks
syn keyword sqlOption    Login_mode
syn keyword sqlOption    Login_procedure
syn keyword sqlOption    Materialized_view_optimization
syn keyword sqlOption    Max_client_statements_cached
syn keyword sqlOption    Max_cursor_count
syn keyword sqlOption    Max_hash_size
syn keyword sqlOption    Max_plans_cached
syn keyword sqlOption    Max_priority
syn keyword sqlOption    Max_query_tasks
syn keyword sqlOption    Max_recursive_iterations
syn keyword sqlOption    Max_statement_count
syn keyword sqlOption    Max_temp_space
syn keyword sqlOption    Min_password_length
syn keyword sqlOption    Nearest_century
syn keyword sqlOption    Non_keywords
syn keyword sqlOption    Odbc_describe_binary_as_varbinary
syn keyword sqlOption    Odbc_distinguish_char_and_varchar
syn keyword sqlOption    Oem_string
syn keyword sqlOption    On_charset_conversion_failure
syn keyword sqlOption    On_tsql_error
syn keyword sqlOption    Optimization_goal
syn keyword sqlOption    Optimization_level
syn keyword sqlOption    Optimization_workload
syn keyword sqlOption    Pinned_cursor_percent_of_cache
syn keyword sqlOption    Post_login_procedure
syn keyword sqlOption    Precision
syn keyword sqlOption    Prefetch
syn keyword sqlOption    Preserve_source_format
syn keyword sqlOption    Prevent_article_pkey_update
syn keyword sqlOption    Priority
syn keyword sqlOption    Query_mem_timeout
syn keyword sqlOption    Quoted_identifier
syn keyword sqlOption    Read_past_deleted
syn keyword sqlOption    Recovery_time
syn keyword sqlOption    Remote_idle_timeout
syn keyword sqlOption    Replicate_all
syn keyword sqlOption    Request_timeout
syn keyword sqlOption    Return_date_time_as_string
syn keyword sqlOption    Rollback_on_deadlock
syn keyword sqlOption    Row_counts
syn keyword sqlOption    Scale
syn keyword sqlOption    Secure_feature_key
syn keyword sqlOption    Sort_collation
syn keyword sqlOption    Sql_flagger_error_level
syn keyword sqlOption    Sql_flagger_warning_level
syn keyword sqlOption    String_rtruncation
syn keyword sqlOption    Subsume_row_locks
syn keyword sqlOption    Suppress_tds_debugging
syn keyword sqlOption    Synchronize_mirror_on_commit
syn keyword sqlOption    Tds_empty_string_is_null
syn keyword sqlOption    Temp_space_limit_check
syn keyword sqlOption    Time_format
syn keyword sqlOption    Time_zone_adjustment
syn keyword sqlOption    Timestamp_format
syn keyword sqlOption    Truncate_timestamp_values
syn keyword sqlOption    Tsql_outer_joins
syn keyword sqlOption    Tsql_variables
syn keyword sqlOption    Updatable_statement_isolation
syn keyword sqlOption    Update_statistics
syn keyword sqlOption    Upgrade_database_capability
syn keyword sqlOption    User_estimates
syn keyword sqlOption    Verify_password_function
syn keyword sqlOption    Wait_for_commit
syn keyword sqlOption    Webservice_namespace_host

" Strings and characters:
syn region sqlString		start=+"+    end=+"+ contains=@Spell
syn region sqlString		start=+'+    end=+'+ contains=@Spell

" Numbers:
syn match sqlNumber		"-\=\<\d*\.\=[0-9_]\>"

" Comments:
syn region sqlDashComment	start=/--/ end=/$/ contains=@Spell
syn region sqlSlashComment	start=/\/\// end=/$/ contains=@Spell
syn region sqlMultiComment	start="/\*" end="\*/" contains=sqlMultiComment,@Spell
syn cluster sqlComment	contains=sqlDashComment,sqlSlashComment,sqlMultiComment,@Spell
syn sync ccomment sqlComment
syn sync ccomment sqlDashComment
syn sync ccomment sqlSlashComment

" Define the default highlighting.
" For version 5.7 and earlier: only when not done already
" For version 5.8 and later: only when an item doesn't have highlighting yet
if version >= 508 || !exists("did_sql_syn_inits")
    if version < 508
        let did_sql_syn_inits = 1
        command -nargs=+ HiLink hi link <args>
    else
        command -nargs=+ HiLink hi link <args>
    endif

    HiLink sqlDashComment	Comment
    HiLink sqlSlashComment	Comment
    HiLink sqlMultiComment	Comment
    HiLink sqlNumber	        Number
    HiLink sqlOperator	        Operator
    HiLink sqlSpecial	        Special
    HiLink sqlKeyword	        Keyword
    HiLink sqlStatement	        Statement
    HiLink sqlString	        String
    HiLink sqlType	        Type
    HiLink sqlFunction	        Function
    HiLink sqlOption	        PreProc

    delcommand HiLink
endif

let b:current_syntax = "sqlanywhere"

" vim:sw=4:
