*&---------------------------------------------------------------------*
*& Report ZBY_YETKI_YONETIM
*&---------------------------------------------------------------------*
*& Süreli (acil / firefighter) yetki talep – onay – Basis tanımlama
*& – izleme
*&
*& Tamamen bağımsız Z çözüm: yalnızca standart SAP fonksiyonları,
*& BAPI'ler ve tablolar kullanılır (SecurityBridge vb. üçüncü parti
*& bağımlılığı yok).
*&
*& Süreç
*&  1. TALEP (ZBY_TALEP) : Kullanıcı kendisi için tarih/saat aralığı
*&           ve gerekçe girer -> ZBY_KULLANICI tablosundaki ONAYCI (O)
*&           kullanıcılara e-posta gider.
*&  2. ONAY  (ZBY_ONAY)  : Onaycı onaylar/reddeder. Onayda BASIS (B)
*&           ekibine e-posta gider.
*&  3. BASIS (ZBY_BASIS) : Basis, kesin tarih/saat aralığını girerek
*&           rolü (varsayılan Z_SURELI_YETKI) tanımlar. Başlangıç
*&           ileri tarihliyse job zamanı gelince rolü atar.
*&  4. BİTİŞ             : Süre dolunca (job) ya da kullanıcı
*&           ZBY_TALEP'te "Süreci tamamla" dediğinde rol geri alınır.
*&  5. RAPOR (ZBY_RAPOR) : Yetki süresince kullanıcının yaptığı
*&           işlemler (işlem kodları/programlar – STAD, değişiklik
*&           belgeleri, tablo logları, arka plan job'ları, transport
*&           talepleri) raporlanır ve sonuç özeti e-postayla gönderilir.
*&
*& Ayarlar : ZBY_PARAM (parametreler),
*&           ZBY_KULLANICI (onaycı/basis/denetçi)
*& Veri    : ZBY_TALEP, ZBY_HAREKET, ZBY_LOG
*& Job     : Bu program, "Arka plan job" modunda 5-15 dk'da bir
*& Sürüm   : SAP NetWeaver 7.40 SP08+
*&---------------------------------------------------------------------*
REPORT zby_yetki_yonetim.

TYPE-POOLS: abap, icon.

TABLES zby_talep.

*----------------------------------------------------------------------*
* Sabitler
*----------------------------------------------------------------------*
CONSTANTS:
  BEGIN OF gc_st,
    pending   TYPE zby_talep-status VALUE 'N',   " Onay bekliyor
    " Onaylandı - Basis bekliyor
    approved  TYPE zby_talep-status VALUE 'O',
    " Tanımlandı - başlangıç bekleniyor
    planned   TYPE zby_talep-status VALUE 'P',
    active    TYPE zby_talep-status VALUE 'A',   " Yetki aktif
    completed TYPE zby_talep-status VALUE 'T',   " Kullanıcı tamamladı
    expired   TYPE zby_talep-status VALUE 'E',   " Süre doldu
    " Basis erken sonlandırdı
    stopped   TYPE zby_talep-status VALUE 'S',
    rejected  TYPE zby_talep-status VALUE 'R',   " Reddedildi
    cancelled TYPE zby_talep-status VALUE 'C',   " Kullanıcı iptal etti
  END OF gc_st,
  BEGIN OF gc_mode,
    request TYPE c VALUE 'T',                    " Yeni talep
    my      TYPE c VALUE 'M',                    " Taleplerim
    approve TYPE c VALUE 'O',                    " Onay
    basis   TYPE c VALUE 'B',                    " Basis tanımlama
    report  TYPE c VALUE 'R',                    " Rapor
    job     TYPE c VALUE 'J',                    " Arka plan job
  END OF gc_mode,
  BEGIN OF gc_utype,
    approver TYPE zby_kullanici-user_type VALUE 'O',
    basis    TYPE zby_kullanici-user_type VALUE 'B',
    auditor  TYPE zby_kullanici-user_type VALUE 'D',
  END OF gc_utype,
  gc_default_role TYPE agr_name VALUE 'Z_SURELI_YETKI'.

*----------------------------------------------------------------------*
* Tipler
*----------------------------------------------------------------------*
TYPES:
  ty_t_talep TYPE STANDARD TABLE OF zby_talep WITH DEFAULT KEY,
  ty_t_act   TYPE STANDARD TABLE OF zby_hareket WITH DEFAULT KEY,
  ty_t_agr   TYPE STANDARD TABLE OF bapiagr WITH DEFAULT KEY,
  ty_t_ret   TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY,
  ty_c30     TYPE c LENGTH 30.

TYPES: BEGIN OF ty_rcpt,
         bname TYPE xubname,
         email TYPE ad_smtpadr,
       END OF ty_rcpt,
       ty_t_rcpt TYPE STANDARD TABLE OF ty_rcpt WITH DEFAULT KEY.

TYPES: BEGIN OF ty_list.
        INCLUDE TYPE zby_talep.
TYPES:  status_txt TYPE ty_c30,
        i_approve  TYPE icon_d,
        i_reject   TYPE icon_d,
        i_grant    TYPE icon_d,
        i_end      TYPE icon_d,
        i_report   TYPE icon_d,
      END OF ty_list,
      ty_t_list TYPE STANDARD TABLE OF ty_list WITH DEFAULT KEY.

DATA: gv_fixed_mode TYPE c,          " İşlem kodundan belirlenen mod
      gv_mode       TYPE c.

*----------------------------------------------------------------------*
* Seçim ekranı 1000
*----------------------------------------------------------------------*
* Mod seçimi (SE38'den çalıştırıldığında görünür)
SELECTION-SCREEN BEGIN OF BLOCK bm WITH FRAME TITLE gv_tm.
PARAMETERS: rb_tlp  RADIOBUTTON GROUP mod DEFAULT 'X' USER-COMMAND mod
            MODIF ID mod,
            rb_onay RADIOBUTTON GROUP mod MODIF ID mod,
            rb_bas  RADIOBUTTON GROUP mod MODIF ID mod,
            rb_rap  RADIOBUTTON GROUP mod MODIF ID mod,
            rb_job  RADIOBUTTON GROUP mod MODIF ID mod.
SELECTION-SCREEN END OF BLOCK bm.

* Talep eden: yeni talep / taleplerim
SELECTION-SCREEN BEGIN OF BLOCK bq WITH FRAME TITLE gv_tq.
PARAMETERS: rb_new RADIOBUTTON GROUP rq DEFAULT 'X' USER-COMMAND rq
            MODIF ID rqm,
            rb_my  RADIOBUTTON GROUP rq MODIF ID rqm.
SELECTION-SCREEN END OF BLOCK bq.

* Yeni talep
SELECTION-SCREEN BEGIN OF BLOCK bt WITH FRAME TITLE gv_tt.
PARAMETERS: p_role  TYPE agr_name MODIF ID tro,
            p_frd   TYPE sydatum  MODIF ID tlp,
            p_frt   TYPE syuzeit  MODIF ID tlp,
            p_tod   TYPE sydatum  MODIF ID tlp,
            p_tot   TYPE syuzeit  MODIF ID tlp,
            p_reas1 TYPE text132  LOWER CASE MODIF ID tlp,
            p_reas2 TYPE text132  LOWER CASE MODIF ID tlp.
SELECTION-SCREEN END OF BLOCK bt.

* Listeler
SELECTION-SCREEN BEGIN OF BLOCK bl WITH FRAME TITLE gv_tl.
SELECT-OPTIONS: s_reqid FOR zby_talep-req_id  MODIF ID lst,
                s_bname FOR zby_talep-bname   MODIF ID lst,
                s_stat  FOR zby_talep-status  MODIF ID lst,
                s_crdat FOR zby_talep-cr_date MODIF ID lst.
SELECTION-SCREEN END OF BLOCK bl.

* Job
SELECTION-SCREEN BEGIN OF BLOCK bj WITH FRAME TITLE gv_tj.
PARAMETERS: p_test AS CHECKBOX MODIF ID job.
SELECTION-SCREEN END OF BLOCK bj.

*----------------------------------------------------------------------*
* Popup 9100 – Basis yetki tanımlama
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF SCREEN 9100 AS WINDOW TITLE gv_t91.
PARAMETERS: p_grole TYPE agr_name OBLIGATORY,
            p_gfd   TYPE sydatum  OBLIGATORY,
            p_gft   TYPE syuzeit,
            p_gtd   TYPE sydatum  OBLIGATORY,
            p_gtt   TYPE syuzeit,
            p_gnote TYPE text132  LOWER CASE.
SELECTION-SCREEN END OF SCREEN 9100.

*----------------------------------------------------------------------*
* Popup 9200 – Not / gerekçe
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF SCREEN 9200 AS WINDOW TITLE gv_t92.
PARAMETERS: p_note TYPE text132 LOWER CASE.
SELECTION-SCREEN END OF SCREEN 9200.

*----------------------------------------------------------------------*
* Konfigürasyon: ZBY_PARAM + ZBY_KULLANICI
*----------------------------------------------------------------------*
CLASS lcl_cfg DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS load.
    CLASS-METHODS param
      IMPORTING iv_name    TYPE csequence
                iv_default TYPE csequence OPTIONAL
      RETURNING VALUE(rv)  TYPE string.
    CLASS-METHODS flag
      IMPORTING iv_name    TYPE csequence
                iv_default TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv)  TYPE abap_bool.
    CLASS-METHODS role
      RETURNING VALUE(rv) TYPE agr_name.
    CLASS-METHODS max_hours
      RETURNING VALUE(rv) TYPE i.
    CLASS-METHODS users
      IMPORTING iv_type   TYPE zby_kullanici-user_type
      RETURNING VALUE(rt) TYPE ty_t_rcpt.
    CLASS-METHODS is_user
      IMPORTING iv_type   TYPE zby_kullanici-user_type
                iv_uname  TYPE syuname DEFAULT sy-uname
      RETURNING VALUE(rv) TYPE abap_bool.
    CLASS-METHODS is_privileged
      RETURNING VALUE(rv) TYPE abap_bool.
  PRIVATE SECTION.
    CLASS-DATA: mt_param  TYPE STANDARD TABLE OF zby_param
                WITH DEFAULT KEY,
                mt_user   TYPE STANDARD TABLE OF zby_kullanici
                  WITH DEFAULT KEY,
                mv_loaded TYPE abap_bool.
ENDCLASS.

CLASS lcl_cfg IMPLEMENTATION.

  METHOD load.
    CHECK mv_loaded = abap_false.
    SELECT * FROM zby_param INTO TABLE mt_param.
    SELECT * FROM zby_kullanici INTO TABLE mt_user WHERE
      active = abap_true.
    mv_loaded = abap_true.
  ENDMETHOD.

  METHOD param.
    DATA ls_param TYPE zby_param.

    load( ).
    READ TABLE mt_param INTO ls_param WITH KEY param = iv_name.
    IF sy-subrc = 0 AND ls_param-value IS NOT INITIAL.
      rv = ls_param-value.
      CONDENSE rv.
    ELSE.
      rv = iv_default.
    ENDIF.
  ENDMETHOD.

  METHOD flag.
    DATA lv_default TYPE string.

    lv_default = iv_default.
    rv = xsdbool( param( iv_name = iv_name
                  iv_default = lv_default ) = abap_true ).
  ENDMETHOD.

  METHOD role.
    rv = param( iv_name = 'ROL' iv_default = gc_default_role ).
  ENDMETHOD.

  METHOD max_hours.
*   En fazla 24 saat; ZBY_PARAM-MAKS_SAAT yalnızca daha kısa bir
*   süre belirleyebilir, 24'ü aşan değerler 24'e indirilir
    CONSTANTS lc_cap TYPE i VALUE 24.

    TRY.
        rv = param( iv_name = 'MAKS_SAAT' iv_default = '24' ).
      CATCH cx_sy_conversion_no_number cx_sy_conversion_overflow.
        rv = lc_cap.
    ENDTRY.
    IF rv <= 0 OR rv > lc_cap.
      rv = lc_cap.
    ENDIF.
  ENDMETHOD.

  METHOD users.
    DATA: ls_user TYPE zby_kullanici,
          ls_rcpt TYPE ty_rcpt.

    load( ).
    LOOP AT mt_user INTO ls_user WHERE user_type = iv_type.
      ls_rcpt-bname = ls_user-bname.
      ls_rcpt-email = ls_user-email.
      APPEND ls_rcpt TO rt.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_user.
    load( ).
    READ TABLE mt_user TRANSPORTING NO FIELDS
      WITH KEY bname = iv_uname user_type = iv_type.
    rv = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD is_privileged.
*   Onaycı, Basis ve Denetçi tüm talepleri ve raporları görebilir
    rv = xsdbool( is_user( gc_utype-approver ) = abap_true
               OR is_user( gc_utype-basis )    = abap_true
               OR is_user( gc_utype-auditor )  = abap_true ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Veritabanı, log ve zaman yardımcıları
*----------------------------------------------------------------------*
CLASS lcl_db DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS next_id
      RETURNING VALUE(rv) TYPE zby_talep-req_id.
    CLASS-METHODS log
      IMPORTING iv_id     TYPE zby_talep-req_id
                iv_action TYPE csequence
                iv_msg    TYPE csequence.
    CLASS-METHODS status_text
      IMPORTING iv_status TYPE zby_talep-status
      RETURNING VALUE(rv) TYPE ty_c30.
    CLASS-METHODS to_ts
      IMPORTING iv_date   TYPE sydatum
                iv_time   TYPE syuzeit
      RETURNING VALUE(rv) TYPE timestamp.
    CLASS-METHODS split_ts
      IMPORTING iv_ts   TYPE timestamp
      EXPORTING ev_date TYPE sydatum
                ev_time TYPE syuzeit.
    CLASS-METHODS now_ts
      RETURNING VALUE(rv) TYPE timestamp.
    CLASS-METHODS add_secs
      IMPORTING iv_ts     TYPE timestamp
                iv_secs   TYPE i
      RETURNING VALUE(rv) TYPE timestamp.
    CLASS-METHODS diff_secs
      IMPORTING iv_ts_to   TYPE timestamp
                iv_ts_from TYPE timestamp
      RETURNING VALUE(rv)  TYPE i.
    CLASS-METHODS ts_text
      IMPORTING iv_date   TYPE sydatum
                iv_time   TYPE syuzeit
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_db IMPLEMENTATION.

  METHOD next_id.
    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        tabname        = 'ZBY_TALEP'
        _wait          = abap_true
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      MESSAGE 'Talep numarası alınamadı (ZBY_TALEP kilitli), '
            & 'tekrar deneyin' TYPE 'E'.
    ENDIF.
    SELECT MAX( req_id ) FROM zby_talep INTO rv.
    rv = rv + 1.
  ENDMETHOD.

  METHOD log.
    DATA ls_log TYPE zby_log.

    ls_log-req_id = iv_id.
    GET TIME STAMP FIELD ls_log-log_ts.
    ls_log-uname  = sy-uname.
    ls_log-action = iv_action.
    ls_log-msg    = iv_msg.
    INSERT zby_log FROM ls_log.
    IF sy-subrc <> 0.
      ls_log-log_ts = ls_log-log_ts + '0.000001'.
      INSERT zby_log FROM ls_log.
    ENDIF.
  ENDMETHOD.

  METHOD status_text.
    CASE iv_status.
      WHEN gc_st-pending.   rv = 'Onay bekliyor'.
      WHEN gc_st-approved.  rv = 'Onaylandı - Basis bekliyor'.
      WHEN gc_st-planned.   rv = 'Tanımlandı - başlangıç bekl.'.
      WHEN gc_st-active.    rv = 'Yetki aktif'.
      WHEN gc_st-completed. rv = 'Kullanıcı tamamladı'.
      WHEN gc_st-expired.   rv = 'Süre doldu'.
      WHEN gc_st-stopped.   rv = 'Basis sonlandırdı'.
      WHEN gc_st-rejected.  rv = 'Reddedildi'.
      WHEN gc_st-cancelled. rv = 'İptal edildi'.
      WHEN OTHERS.          rv = iv_status.
    ENDCASE.
  ENDMETHOD.

  METHOD to_ts.
*   Sistem saatinde "yerel" zaman damgası (YYYYMMDDhhmmss)
    DATA lv_c TYPE c LENGTH 14.

    lv_c = |{ iv_date }{ iv_time }|.
    rv = lv_c.
  ENDMETHOD.

  METHOD split_ts.
    DATA lv_c TYPE c LENGTH 14.

    lv_c = |{ iv_ts }|.
    ev_date = lv_c(8).
    ev_time = lv_c+8(6).
  ENDMETHOD.

  METHOD now_ts.
    GET TIME.
    rv = to_ts( iv_date = sy-datum iv_time = sy-uzeit ).
  ENDMETHOD.

  METHOD add_secs.
    TRY.
        rv = cl_abap_tstmp=>add( tstmp = iv_ts secs = iv_secs ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        rv = iv_ts.
    ENDTRY.
  ENDMETHOD.

  METHOD diff_secs.
    TRY.
        rv = cl_abap_tstmp=>subtract( tstmp1 = iv_ts_to
                                      tstmp2 = iv_ts_from ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        rv = 0.
    ENDTRY.
  ENDMETHOD.

  METHOD ts_text.
    rv = |{ iv_date DATE = USER } { iv_time TIME = USER }|.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Rol atama / geri alma (standart kullanıcı BAPI'leri)
*----------------------------------------------------------------------*
CLASS lcl_role DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS assign
      IMPORTING iv_bname    TYPE xubname
                iv_role     TYPE agr_name
                iv_from     TYPE sydatum
                iv_to       TYPE sydatum
      EXPORTING ev_preexist TYPE abap_bool
                ev_ok       TYPE abap_bool
                ev_msg      TYPE string.
    CLASS-METHODS remove
      IMPORTING iv_bname TYPE xubname
                iv_role  TYPE agr_name
                iv_from  TYPE sydatum
                iv_to    TYPE sydatum
      EXPORTING ev_ok    TYPE abap_bool
                ev_msg   TYPE string.
    CLASS-METHODS role_exists
      IMPORTING iv_role   TYPE agr_name
      RETURNING VALUE(rv) TYPE abap_bool.
  PRIVATE SECTION.
    CLASS-METHODS read_roles
      IMPORTING iv_bname TYPE xubname
      EXPORTING et_roles TYPE ty_t_agr
                ev_ok    TYPE abap_bool
                ev_msg   TYPE string.
    CLASS-METHODS write_roles
      IMPORTING iv_bname TYPE xubname
                it_roles TYPE ty_t_agr
      EXPORTING ev_ok    TYPE abap_bool
                ev_msg   TYPE string.
    CLASS-METHODS first_error
      IMPORTING it_ret    TYPE ty_t_ret
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_role IMPLEMENTATION.

  METHOD role_exists.
    DATA lv_dummy TYPE agr_name.

    SELECT SINGLE agr_name FROM agr_define INTO lv_dummy
      WHERE agr_name = iv_role.
    rv = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD read_roles.
    DATA lt_ret TYPE ty_t_ret.

    CLEAR: et_roles, ev_ok, ev_msg.
    CALL FUNCTION 'BAPI_USER_GET_DETAIL'
      EXPORTING
        username       = iv_bname
        cache_results  = space
      TABLES
        activitygroups = et_roles
        return         = lt_ret.
    ev_msg = first_error( lt_ret ).
    ev_ok  = xsdbool( ev_msg IS INITIAL ).
  ENDMETHOD.

  METHOD write_roles.
    DATA: lt_roles TYPE ty_t_agr,
          lt_ret   TYPE ty_t_ret.

    CLEAR: ev_ok, ev_msg.
    lt_roles = it_roles.
    CALL FUNCTION 'BAPI_USER_ACTGROUPS_ASSIGN'
      EXPORTING
        username       = iv_bname
      TABLES
        activitygroups = lt_roles
        return         = lt_ret.

    ev_msg = first_error( lt_ret ).
    IF ev_msg IS NOT INITIAL.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      RETURN.
    ENDIF.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.
    ev_ok = abap_true.
  ENDMETHOD.

  METHOD assign.
    DATA: lt_roles TYPE ty_t_agr,
          ls_role  TYPE bapiagr.

    CLEAR: ev_preexist, ev_ok, ev_msg.
    read_roles( EXPORTING iv_bname = iv_bname
                IMPORTING et_roles = lt_roles ev_ok = ev_ok
                ev_msg = ev_msg ).
    IF ev_ok = abap_false.
      RETURN.
    ENDIF.

*   Kullanıcı rolü tüm süre boyunca zaten taşıyorsa ek atama yapılmaz
    LOOP AT lt_roles INTO ls_role WHERE agr_name = iv_role.
      IF ls_role-from_dat <= iv_from AND ls_role-to_dat >= iv_to.
        ev_preexist = abap_true.
        ev_msg = |Kullanıcı { iv_role } rolüne zaten sahip, |
              && |ek atama yapılmadı|.
        RETURN.
      ENDIF.
    ENDLOOP.

*   Mevcut atamalar korunur; yeni satır tarih sınırlı eklenir.
*   TO_DAT sayesinde job çalışmasa bile yetki en geç gün sonunda biter.
    CLEAR ls_role.
    ls_role-agr_name = iv_role.
    ls_role-from_dat = iv_from.
    ls_role-to_dat   = iv_to.
    APPEND ls_role TO lt_roles.

    write_roles( EXPORTING iv_bname = iv_bname it_roles = lt_roles
                 IMPORTING ev_ok = ev_ok ev_msg = ev_msg ).
    IF ev_ok = abap_true.
      ev_msg = |{ iv_role } rolü { iv_bname } kullanıcısına atandı|.
    ENDIF.
  ENDMETHOD.

  METHOD remove.
    DATA lt_roles TYPE ty_t_agr.

    CLEAR: ev_ok, ev_msg.
    read_roles( EXPORTING iv_bname = iv_bname
                IMPORTING et_roles = lt_roles ev_ok = ev_ok
                ev_msg = ev_msg ).
    IF ev_ok = abap_false.
      RETURN.
    ENDIF.

*   Yalnızca bu talebin eklediği atama satırı silinir
    DELETE lt_roles WHERE agr_name = iv_role
                      AND from_dat = iv_from
                      AND to_dat   = iv_to.
    IF sy-subrc <> 0.
      ev_ok  = abap_true.
      ev_msg = 'Rol ataması bulunamadı (zaten kaldırılmış)'.
      RETURN.
    ENDIF.

    write_roles( EXPORTING iv_bname = iv_bname it_roles = lt_roles
                 IMPORTING ev_ok = ev_ok ev_msg = ev_msg ).
    IF ev_ok = abap_true.
      ev_msg = |{ iv_role } rolü geri alındı|.
    ENDIF.
  ENDMETHOD.

  METHOD first_error.
    DATA ls_ret TYPE bapiret2.

    LOOP AT it_ret INTO ls_ret
      WHERE type = 'E' OR type = 'A' OR type = 'X'.
      rv = ls_ret-message.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* E-posta (SAPconnect / SCOT)
*----------------------------------------------------------------------*
CLASS lcl_mail DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS send
      IMPORTING it_rcpt    TYPE ty_t_rcpt
                iv_subject TYPE csequence
                it_body    TYPE soli_tab.
    CLASS-METHODS user_rcpt
      IMPORTING iv_bname  TYPE xubname
      RETURNING VALUE(rs) TYPE ty_rcpt.
    CLASS-METHODS req_body
      IMPORTING is_req    TYPE zby_talep
                iv_intro  TYPE csequence
                iv_action TYPE csequence OPTIONAL
      RETURNING VALUE(rt) TYPE soli_tab.
    CLASS-METHODS add_line
      IMPORTING iv_text TYPE csequence
      CHANGING  ct_body TYPE soli_tab.
  PRIVATE SECTION.
    CLASS-METHODS to_html
      IMPORTING iv_title  TYPE csequence
                it_body   TYPE soli_tab
      RETURNING VALUE(rv) TYPE string.
    CLASS-METHODS enc
      IMPORTING iv_text   TYPE csequence
      RETURNING VALUE(rv) TYPE string.
ENDCLASS.

CLASS lcl_mail IMPLEMENTATION.

  METHOD send.
*   Standart BCS (CL_BCS) ile HTML e-posta. Gönderen adres
*   ZBY_PARAM-MAIL_GONDEREN'den okunur; boşsa SAP, çalıştıran
*   kullanıcının (job'da job kullanıcısının) adresini kullanır.
*   COMMIT WORK çağıran süreçte yapılır.
    DATA: lt_to     TYPE STANDARD TABLE OF ad_smtpadr,
          lv_to     TYPE ad_smtpadr,
          lt_html   TYPE soli_tab,
          lo_bcs    TYPE REF TO cl_bcs,
          lo_doc    TYPE REF TO cl_document_bcs,
          lo_sender TYPE REF TO if_sender_bcs,
          lo_rcpt   TYPE REF TO if_recipient_bcs,
          lx_bcs    TYPE REF TO cx_bcs,
          lv_err    TYPE string,
          ls_rcpt   TYPE ty_rcpt,
          ls_soli   TYPE soli,
          lv_html   TYPE string,
          lv_len    TYPE i,
          lv_off    TYPE i,
          lv_cut    TYPE i,
          lv_pos    TYPE i,
          lv_subj   TYPE so_obj_des,
          lv_subjl  TYPE string,
          lv_sender TYPE ad_smtpadr.

    CHECK it_rcpt IS NOT INITIAL.

*   Alıcılar: e-posta yoksa SU01 adresi kullanılır
    LOOP AT it_rcpt INTO ls_rcpt.
      IF ls_rcpt-email IS INITIAL AND ls_rcpt-bname IS NOT INITIAL.
        ls_rcpt-email = user_rcpt( ls_rcpt-bname )-email.
      ENDIF.
      CHECK ls_rcpt-email IS NOT INITIAL.
      lv_to = ls_rcpt-email.
      READ TABLE lt_to TRANSPORTING NO FIELDS
        WITH KEY table_line = lv_to.
      CHECK sy-subrc <> 0.
      APPEND lv_to TO lt_to.
    ENDLOOP.
    IF lt_to IS INITIAL.
      MESSAGE 'E-posta gönderilmedi: alıcı adresi bulunamadı'
        TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

*   Konu: fazla boşluklar ve özel tire temizlenir
    lv_subjl = condense( val = iv_subject ).
    REPLACE ALL OCCURRENCES OF '–' IN lv_subjl WITH '-'.
    lv_subj  = lv_subjl.

*   HTML gövde tek metin olarak üretilir ve 255'lik parçalara
*   bölünür (BCS, SOLI satırlarını aynen birleştirir)
    lv_html = to_html( iv_title = lv_subjl it_body = it_body ).
    lv_len  = strlen( lv_html ).
    WHILE lv_off < lv_len.
      lv_cut = lv_len - lv_off.
      IF lv_cut > 255.
        lv_cut = 255.
*       Parça boşlukla bitmesin (satır sonu boşlukları kaybolabilir)
        DO.
          lv_pos = lv_off + lv_cut - 1.
          IF lv_cut <= 1 OR lv_html+lv_pos(1) <> ` `.
            EXIT.
          ENDIF.
          lv_cut = lv_cut - 1.
        ENDDO.
      ENDIF.
      ls_soli-line = substring( val = lv_html off = lv_off
                                len = lv_cut ).
      APPEND ls_soli TO lt_html.
      lv_off = lv_off + lv_cut.
    ENDWHILE.

    lv_sender = lcl_cfg=>param( iv_name = 'MAIL_GONDEREN' ).

    TRY.
        lo_bcs = cl_bcs=>create_persistent( ).
        lo_doc = cl_document_bcs=>create_document(
                   i_type    = 'HTM'
                   i_text    = lt_html
                   i_subject = lv_subj ).
        lo_bcs->set_document( lo_doc ).
*       50 karakterden uzun konular kısaltılmadan gönderilir
        lo_bcs->set_message_subject( ip_subject = lv_subjl ).

        IF lv_sender IS NOT INITIAL.
          lo_sender = cl_cam_address_bcs=>create_internet_address(
                        i_address_string = lv_sender ).
          lo_bcs->set_sender( lo_sender ).
        ENDIF.

        LOOP AT lt_to INTO lv_to.
          lo_rcpt = cl_cam_address_bcs=>create_internet_address(
                      i_address_string = lv_to ).
          lo_bcs->add_recipient( i_recipient = lo_rcpt ).
        ENDLOOP.

        lo_bcs->set_send_immediately( abap_true ).
        lo_bcs->send( i_with_error_screen = space ).
      CATCH cx_bcs INTO lx_bcs.
        lv_err = |E-posta gönderilemedi: { lx_bcs->get_text( ) }|.
        MESSAGE lv_err TYPE 'S' DISPLAY LIKE 'W'.
    ENDTRY.
  ENDMETHOD.

  METHOD user_rcpt.
*   Kullanıcının SU01'deki e-posta adresi
    rs-bname = iv_bname.
    SELECT SINGLE a~smtp_addr INTO rs-email
      FROM usr21 AS u
      INNER JOIN adr6 AS a ON a~addrnumber = u~addrnumber
                          AND a~persnumber = u~persnumber
      WHERE u~bname = iv_bname.
  ENDMETHOD.

  METHOD add_line.
    DATA ls_line TYPE soli.

    ls_line-line = iv_text.
    APPEND ls_line TO ct_body.
  ENDMETHOD.

  METHOD to_html.
*   Metin satırlarından düzenli HTML üretir:
*     "Etiket : Değer" satırları  -> iki kolonlu tablo
*     ardından tablo gelen metin -> bölüm başlığı
*     diğer metinler             -> paragraf
    DATA: ls_body  TYPE soli,
          ls_next  TYPE soli,
          lv_line  TYPE string,
          lv_next  TYPE string,
          lv_key   TYPE string,
          lv_val   TYPE string,
          lv_off   TYPE i,
          lv_idx   TYPE i,
          lv_intab TYPE abap_bool,
          lv_first TYPE abap_bool VALUE abap_true.

    rv = `<html><head><meta http-equiv="Content-Type" `
      && `content="text/html; charset=utf-8"></head>`
      && `<body style="margin:0;padding:16px;background:#f3f4f6;`
      && `font-family:Arial,Helvetica,sans-serif;font-size:14px;`
      && `color:#1f2937">`
      && `<table width="100%" cellpadding="0" cellspacing="0" `
      && `style="max-width:680px;background:#ffffff;`
      && `border:1px solid #d1d5db">`
      && `<tr><td style="background:#1f4e79;color:#ffffff;`
      && `padding:14px 20px;font-size:16px;font-weight:bold">`
      && enc( iv_title ) && `</td></tr>`
      && `<tr><td style="padding:16px 20px">`.

    LOOP AT it_body INTO ls_body.
      lv_idx  = sy-tabix + 1.
      lv_line = ls_body-line.
      SHIFT lv_line LEFT DELETING LEADING space.

*     Boş satır: açık tablo kapanır
      IF lv_line IS INITIAL.
        IF lv_intab = abap_true.
          rv = rv && `</table>`.
          lv_intab = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

*     "Etiket : Değer" satırı
      FIND FIRST OCCURRENCE OF ` : ` IN lv_line
        MATCH OFFSET lv_off.
      IF sy-subrc = 0.
        lv_key = substring( val = lv_line len = lv_off ).
        lv_off = lv_off + 3.
        lv_val = substring( val = lv_line off = lv_off ).
        lv_key = condense( val = lv_key ).
        lv_val = condense( val = lv_val ).
        IF lv_intab = abap_false.
          rv = rv && `<table cellpadding="6" cellspacing="0" `
                  && `style="border-collapse:collapse;width:100%;`
                  && `margin:6px 0 14px 0">`.
          lv_intab = abap_true.
        ENDIF.
        rv = rv && `<tr><td style="width:170px;color:#6b7280;`
                && `border-bottom:1px solid #e5e7eb;`
                && `vertical-align:top">` && enc( lv_key )
                && `</td><td style="border-bottom:1px solid `
                && `#e5e7eb;font-weight:bold">` && enc( lv_val )
                && `</td></tr>`.
        lv_first = abap_false.
        CONTINUE.
      ENDIF.

      IF lv_intab = abap_true.
        rv = rv && `</table>`.
        lv_intab = abap_false.
      ENDIF.

*     Sonraki satır tablo satırıysa bu metin bölüm başlığıdır
      CLEAR: ls_next, lv_next.
      READ TABLE it_body INTO ls_next INDEX lv_idx.
      IF sy-subrc = 0.
        lv_next = ls_next-line.
      ENDIF.
      FIND ` : ` IN lv_next.
      IF sy-subrc = 0 AND lv_first = abap_false.
        rv = rv && `<div style="margin:16px 0 4px 0;font-size:15px;`
                && `font-weight:bold;color:#1f4e79">`
                && enc( lv_line ) && `</div>`.
      ELSE.
        rv = rv && `<p style="margin:0 0 10px 0">`
                && enc( lv_line ) && `</p>`.
      ENDIF.
      lv_first = abap_false.
    ENDLOOP.
    IF lv_intab = abap_true.
      rv = rv && `</table>`.
    ENDIF.

    rv = rv && `</td></tr><tr><td style="padding:10px 20px;`
            && `background:#f9fafb;border-top:1px solid #e5e7eb;`
            && `font-size:12px;color:#6b7280">`
            && enc( `Bu e-posta otomatik olarak gönderilmektedir. `
                 && `Lütfen cevap vermeyiniz.` )
            && `</td></tr></table></body></html>`.
  ENDMETHOD.

  METHOD enc.
*   HTML kaçışı + ASCII dışı karakterler sayısal varlık (&#305;)
*   olarak yazılır; Türkçe karakterler her istemcide doğru görünür
    DATA: lv_s  TYPE string,
          lv_c  TYPE c LENGTH 1,
          lv_i  TYPE i,
          lv_n  TYPE i,
          lv_cp TYPE i.

    lv_s = escape( val = iv_text format = cl_abap_format=>e_html_text ).
    lv_n = strlen( lv_s ).
    DO lv_n TIMES.
      lv_i  = sy-index - 1.
      lv_c  = lv_s+lv_i(1).
      lv_cp = cl_abap_conv_out_ce=>uccpi( lv_c ).
      IF lv_cp > 127.
        rv = rv && |&#{ lv_cp };|.
      ELSE.
        rv = rv && substring( val = lv_s off = lv_i len = 1 ).
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD req_body.
    DATA: lv_line TYPE string,
          lv_from TYPE string,
          lv_to   TYPE string.

    add_line( EXPORTING iv_text = iv_intro CHANGING ct_body = rt ).
    add_line( EXPORTING iv_text = space CHANGING ct_body = rt ).

    lv_line = |Talep No          : { is_req-req_id ALPHA = OUT }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    lv_line = |Kullanıcı         : { is_req-bname }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    lv_line = |Rol               : { is_req-agr_name }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).

    lv_from = lcl_db=>ts_text( iv_date = is_req-req_from_date
                               iv_time = is_req-req_from_time ).
    lv_to   = lcl_db=>ts_text( iv_date = is_req-req_to_date
                               iv_time = is_req-req_to_time ).
    lv_line = |İstenen aralık    : { lv_from } - { lv_to }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).

    IF is_req-valid_from_date IS NOT INITIAL.
      lv_from = lcl_db=>ts_text( iv_date = is_req-valid_from_date
                                 iv_time = is_req-valid_from_time ).
      lv_to   = lcl_db=>ts_text( iv_date = is_req-valid_to_date
                                 iv_time = is_req-valid_to_time ).
      lv_line = |Tanımlanan aralık : { lv_from } - { lv_to }|.
      add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    ENDIF.

    lv_line = |Ticket            : { is_req-ticket }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    lv_line = |Gerekçe           : { is_req-reason }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    IF is_req-approver IS NOT INITIAL.
      lv_line = |Onaycı            : { is_req-approver } |
             && |{ is_req-appr_note }|.
      add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    ENDIF.
    IF is_req-basis_user IS NOT INITIAL.
      lv_line = |Basis             : { is_req-basis_user } |
             && |{ is_req-basis_note }|.
      add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    ENDIF.
    lv_line = |Durum             : |
           && |{ lcl_db=>status_text( is_req-status ) }|.
    add_line( EXPORTING iv_text = lv_line CHANGING ct_body = rt ).
    IF iv_action IS NOT INITIAL.
      add_line( EXPORTING iv_text = space CHANGING ct_body = rt ).
      add_line( EXPORTING iv_text = iv_action CHANGING ct_body = rt ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Kullanıcı hareketlerini toplama (standart kaynaklar)
*----------------------------------------------------------------------*
CLASS lcl_collector DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS collect
      IMPORTING iv_bname TYPE xubname
                iv_from  TYPE timestamp
                iv_to    TYPE timestamp
      EXPORTING et_act   TYPE ty_t_act
                et_msg   TYPE string_table.
  PRIVATE SECTION.
    CLASS-METHODS read_stad
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_changedocs
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_tablelog
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_jobs
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_transports
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_se16n
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS read_audit
      IMPORTING iv_bname TYPE xubname iv_from TYPE timestamp
                iv_to    TYPE timestamp
      CHANGING  ct_act   TYPE ty_t_act ct_msg TYPE string_table.
    CLASS-METHODS rec_text
      IMPORTING iv_tab    TYPE csequence
                iv_value  TYPE se16n_cd_data-value
      RETURNING VALUE(rv) TYPE string.
    CLASS-METHODS comp
      IMPORTING is_rec    TYPE any
                iv_name   TYPE csequence
      RETURNING VALUE(rv) TYPE string.
    CLASS-METHODS in_window
      IMPORTING iv_date   TYPE sydatum
                iv_time   TYPE syuzeit
                iv_from   TYPE timestamp
                iv_to     TYPE timestamp
      RETURNING VALUE(rv) TYPE abap_bool.
ENDCLASS.

CLASS lcl_collector IMPLEMENTATION.

  METHOD collect.
    CLEAR: et_act, et_msg.
    CHECK iv_from < iv_to.

    IF lcl_cfg=>flag( 'KAYNAK_STAD' ) = abap_true.
      read_stad( EXPORTING iv_bname = iv_bname iv_from = iv_from
                 iv_to = iv_to
                 CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_CD' ) = abap_true.
      read_changedocs( EXPORTING iv_bname = iv_bname iv_from = iv_from
                       iv_to = iv_to
                       CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_TABLOG' ) = abap_true.
      read_tablelog( EXPORTING iv_bname = iv_bname iv_from = iv_from
                     iv_to = iv_to
                     CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_JOB' ) = abap_true.
      read_jobs( EXPORTING iv_bname = iv_bname iv_from = iv_from
                 iv_to = iv_to
                 CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_TRANSPORT' ) = abap_true.
      read_transports( EXPORTING iv_bname = iv_bname iv_from = iv_from
                       iv_to = iv_to
                       CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_SE16N' ) = abap_true.
      read_se16n( EXPORTING iv_bname = iv_bname iv_from = iv_from
                  iv_to = iv_to
                  CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.
    IF lcl_cfg=>flag( 'KAYNAK_AUDIT' ) = abap_true.
      read_audit( EXPORTING iv_bname = iv_bname iv_from = iv_from
                  iv_to = iv_to
                  CHANGING ct_act = et_act ct_msg = et_msg ).
    ENDIF.

    SORT et_act BY datum uzeit source.
  ENDMETHOD.

  METHOD in_window.
*   Pencere [from, to) – ardışık toplamalarda tekrar oluşmaz
    DATA lv_ts TYPE timestamp.

    lv_ts = lcl_db=>to_ts( iv_date = iv_date iv_time = iv_time ).
    rv = xsdbool( lv_ts >= iv_from AND lv_ts < iv_to ).
  ENDMETHOD.

*----------------------------------------------------------------------
* 1) İşlem kodları / programlar – iş yükü istatistikleri (STAD)
*----------------------------------------------------------------------
  METHOD read_stad.
    DATA: lt_stats    TYPE stad_allstats,
          lt_prot     TYPE STANDARD TABLE OF sapwlminut,
          lt_rfcret   TYPE STANDARD TABLE OF sapwlsfrer,
          lt_srv      TYPE STANDARD TABLE OF msxxlist,
          lv_problems TYPE int4,
          lv_readtime TYPE swncuzeit,
          lv_ts       TYPE timestamp,
          lv_next     TYPE timestamp,
          lv_secs     TYPE i,
          lv_date     TYPE sydatum,
          lv_time     TYPE syuzeit,
          ls_act      TYPE zby_hareket,
          ls_last     TYPE zby_hareket.

    FIELD-SYMBOLS <ls_stat> TYPE stad_statrec.

*   Başka kullanıcıların istatistiklerini okumak S_TOOLS_EX gerektirir
    AUTHORITY-CHECK OBJECT 'S_TOOLS_EX' ID 'AUTH' FIELD 'S_TOOLS_EX_A'.
    IF sy-subrc <> 0.
      APPEND 'STAD okunamadı: S_TOOLS_EX (S_TOOLS_EX_A) yetkisi yok' TO
        ct_msg.
      RETURN.
    ENDIF.

*   STAD en fazla 2 saatlik dilimler halinde okunur
    lv_ts = iv_from.
    WHILE lv_ts < iv_to.
      lv_next = lcl_db=>add_secs( iv_ts = lv_ts iv_secs = 7200 ).
      IF lv_next > iv_to.
        lv_next = iv_to.
      ENDIF.
      lv_secs     = lcl_db=>diff_secs( iv_ts_to = lv_next
                                       iv_ts_from = lv_ts ).
      lv_readtime = lv_secs.                         " saniye -> hhmmss
      lcl_db=>split_ts( EXPORTING iv_ts = lv_ts
                        IMPORTING ev_date = lv_date ev_time = lv_time ).

      CLEAR: lt_stats, lt_prot, lt_rfcret, lt_srv, lv_problems.
*     SERVER_LIST zorunlu ama boş geçilir: FM sunucuları kendisi bulur
      CALL FUNCTION 'SWNC_STAD_READ_STATRECS'
        EXPORTING
          read_client     = sy-mandt
          read_time       = lv_readtime
          read_start_date = lv_date
          read_start_time = lv_time
          read_username   = iv_bname
          wait_factor     = 10
        IMPORTING
          problems        = lv_problems
        TABLES
          protocol        = lt_prot
          rfc_returns     = lt_rfcret
          server_list     = lt_srv
        CHANGING
          all_stats       = lt_stats
        EXCEPTIONS
          OTHERS          = 1.
      IF sy-subrc <> 0 OR lv_problems <> 0.
        APPEND |STAD { lv_date DATE = USER } { lv_time TIME = USER } |
            && |dilimi eksik okunmuş olabilir| TO ct_msg.
      ENDIF.

      LOOP AT lt_stats ASSIGNING <ls_stat>
        WHERE record-account = iv_bname
          AND record-mandt   = sy-mandt.
        CHECK in_window( iv_date = <ls_stat>-record-startdate
                         iv_time = <ls_stat>-record-starttime
                         iv_from = iv_from iv_to = iv_to ) = abap_true.
        CLEAR ls_act.
        ls_act-datum    = <ls_stat>-record-startdate.
        ls_act-uzeit    = <ls_stat>-record-starttime.
        ls_act-source   = 'İŞLEM'.
        ls_act-tcode    = <ls_stat>-record-tcode.
        ls_act-prog_name = <ls_stat>-record-report.
        ls_act-terminal = <ls_stat>-record-terminalid.
        ls_act-action   = COND #(
          WHEN <ls_stat>-record-tcode IS NOT INITIAL
          THEN 'İşlem kodu / diyalog adımı'
          ELSE 'Program / RFC / arka plan adımı' ).
*       Aynı işlem kodu+program için ardışık diyalog adımları tek satır
        IF ls_act-tcode = ls_last-tcode AND
           ls_act-prog_name = ls_last-prog_name AND
           ls_act-terminal = ls_last-terminal AND
           ls_act-datum = ls_last-datum.
          CONTINUE.
        ENDIF.
        ls_last = ls_act.
        APPEND ls_act TO ct_act.
      ENDLOOP.

      lv_ts = lv_next.
    ENDWHILE.
  ENDMETHOD.

*----------------------------------------------------------------------
* 2) Değişiklik belgeleri (CDHDR/CDPOS) – kullanıcı, rol, ana veri vb.
*----------------------------------------------------------------------
  METHOD read_changedocs.
    DATA: lr_objcl TYPE cdobjectcl_range_tab,
          ls_objcl LIKE LINE OF lr_objcl,
          lr_user  TYPE cdusername_range_tab,
          ls_user  LIKE LINE OF lr_user,
          lt_pos   TYPE STANDARD TABLE OF cdred,
          lv_fd    TYPE sydatum,
          lv_ft    TYPE syuzeit,
          lv_td    TYPE sydatum,
          lv_tt    TYPE syuzeit,
          ls_act   TYPE zby_hareket.

    FIELD-SYMBOLS <ls_pos> LIKE LINE OF lt_pos.

    ls_objcl-sign = 'I'. ls_objcl-option = 'CP'. ls_objcl-low = '*'.
    APPEND ls_objcl TO lr_objcl.
    ls_user-sign = 'I'. ls_user-option = 'EQ'. ls_user-low = iv_bname.
    APPEND ls_user TO lr_user.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_ft ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_tt ).

    CALL FUNCTION 'CHANGEDOCUMENT_READ_RANGES'
      EXPORTING
        date_of_change             = lv_fd
        time_of_change             = lv_ft
        date_until                 = lv_td
        time_until                 = lv_tt
        objectclass_tab            = lr_objcl
        username_tab               = lr_user
      TABLES
        editpos                    = lt_pos
      EXCEPTIONS
        no_position_found          = 1
        wrong_access_to_archive    = 2
        time_zone_conversion_error = 3
        OTHERS                     = 4.
    CASE sy-subrc.
      WHEN 0 OR 1.
      WHEN OTHERS.
        APPEND |Değişiklik belgeleri okunamadı (rc={ sy-subrc })| TO
          ct_msg.
        RETURN.
    ENDCASE.

    LOOP AT lt_pos ASSIGNING <ls_pos>.
      CHECK in_window( iv_date = <ls_pos>-udate iv_time = <ls_pos>-utime
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR ls_act.
      ls_act-datum     = <ls_pos>-udate.
      ls_act-uzeit     = <ls_pos>-utime.
      ls_act-source    = 'DEĞ.BELGESİ'.
      ls_act-tcode     = <ls_pos>-tcode.
      ls_act-object    = |{ <ls_pos>-tabname } { <ls_pos>-objectid } |
                      && |{ <ls_pos>-tabkey }|.
      ls_act-action    = SWITCH string( <ls_pos>-chngind
                           WHEN 'I' THEN 'Ekleme'
                           WHEN 'U' THEN 'Değişiklik'
                           WHEN 'D' THEN 'Silme'
                           WHEN 'E' THEN 'Tekil silme'
                           ELSE <ls_pos>-chngind ).
      ls_act-action    = |{ ls_act-action }: { <ls_pos>-fname }|.
      ls_act-old_value = <ls_pos>-f_old.
      ls_act-new_value = <ls_pos>-f_new.
      ls_act-text      = <ls_pos>-ftext.
      APPEND ls_act TO ct_act.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------
* 3) Tablo değişiklik logu (DBTABLOG – rec/client ve tablo loglama açık
*    tablolar için)
*----------------------------------------------------------------------
  METHOD read_tablelog.
    TYPES: BEGIN OF ty_log,
             logdate  TYPE dbtablog-logdate,
             logtime  TYPE dbtablog-logtime,
             tabname  TYPE dbtablog-tabname,
             logkey   TYPE dbtablog-logkey,
             tcode    TYPE dbtablog-tcode,
             progname TYPE dbtablog-progname,
             optype   TYPE dbtablog-optype,
           END OF ty_log.
    DATA: lt_log TYPE STANDARD TABLE OF ty_log,
          ls_log TYPE ty_log,
          lv_fd  TYPE sydatum,
          lv_td  TYPE sydatum,
          lv_t   TYPE syuzeit,
          ls_act TYPE zby_hareket.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_t ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_t ).

    SELECT logdate logtime tabname logkey tcode progname optype
      FROM dbtablog INTO TABLE lt_log
      WHERE logdate  BETWEEN lv_fd AND lv_td
        AND username = iv_bname.

    LOOP AT lt_log INTO ls_log.
      CHECK in_window( iv_date = ls_log-logdate iv_time = ls_log-logtime
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR ls_act.
      ls_act-datum   = ls_log-logdate.
      ls_act-uzeit   = ls_log-logtime.
      ls_act-source  = 'TABLO LOG'.
      ls_act-tcode   = ls_log-tcode.
      ls_act-prog_name = ls_log-progname.
      ls_act-object  = |{ ls_log-tabname } { ls_log-logkey }|.
      ls_act-action  = SWITCH #( ls_log-optype
                         WHEN 'I' THEN 'Tablo kaydı eklendi'
                         WHEN 'U' THEN 'Tablo kaydı değiştirildi'
                         WHEN 'D' THEN 'Tablo kaydı silindi'
                         ELSE |İşlem { ls_log-optype }| ).
      ls_act-text    = 'Alan bazında detay: SCU3 / RSVTPROT'.
      APPEND ls_act TO ct_act.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------
* 4) Arka plan job'ları (planladığı veya adım kullanıcısı olduğu)
*----------------------------------------------------------------------
  METHOD read_jobs.
    TYPES: BEGIN OF ty_job,
             jobname   TYPE tbtco-jobname,
             jobcount  TYPE tbtco-jobcount,
             sdldate   TYPE tbtco-sdldate,
             sdltime   TYPE tbtco-sdltime,
             strtdate  TYPE tbtco-strtdate,
             strttime  TYPE tbtco-strttime,
             status    TYPE tbtco-status,
             sdluname  TYPE tbtco-sdluname,
             progname  TYPE tbtcp-progname,
             variant   TYPE tbtcp-variant,
             authcknam TYPE tbtcp-authcknam,
           END OF ty_job.
    DATA: lt_job TYPE STANDARD TABLE OF ty_job,
          ls_job TYPE ty_job,
          lv_fd  TYPE sydatum,
          lv_td  TYPE sydatum,
          lv_t   TYPE syuzeit,
          ls_act TYPE zby_hareket.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_t ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_t ).

*   Kullanıcının bu aralıkta planladığı job'lar
    SELECT o~jobname o~jobcount o~sdldate o~sdltime o~strtdate
           o~strttime o~status o~sdluname
           p~progname p~variant p~authcknam
      FROM tbtco AS o INNER JOIN tbtcp AS p
        ON p~jobname = o~jobname AND p~jobcount = o~jobcount
      INTO TABLE lt_job
      WHERE o~sdluname = iv_bname
        AND o~sdldate BETWEEN lv_fd AND lv_td.

    LOOP AT lt_job INTO ls_job.
      CHECK in_window( iv_date = ls_job-sdldate iv_time = ls_job-sdltime
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR ls_act.
      ls_act-datum   = ls_job-sdldate.
      ls_act-uzeit   = ls_job-sdltime.
      ls_act-source  = 'ARKA PLAN JOB'.
      ls_act-prog_name = ls_job-progname.
      ls_act-object  = |{ ls_job-jobname } / { ls_job-jobcount }|.
      ls_act-action  = 'Job planlandı'.
      ls_act-text    = |Varyant: { ls_job-variant } |
                    && |Adım kullanıcısı: { ls_job-authcknam } |
                    && |Durum: { ls_job-status }|.
      APPEND ls_act TO ct_act.
    ENDLOOP.

*   Başkası planlasa da bu kullanıcı adına çalışan job adımları
    CLEAR lt_job.
    SELECT o~jobname o~jobcount o~sdldate o~sdltime o~strtdate
           o~strttime o~status o~sdluname
           p~progname p~variant p~authcknam
      FROM tbtco AS o INNER JOIN tbtcp AS p
        ON p~jobname = o~jobname AND p~jobcount = o~jobcount
      INTO TABLE lt_job
      WHERE p~authcknam = iv_bname
        AND o~sdluname  <> iv_bname
        AND o~strtdate BETWEEN lv_fd AND lv_td.

    LOOP AT lt_job INTO ls_job.
      CHECK in_window( iv_date = ls_job-strtdate
                       iv_time = ls_job-strttime
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR ls_act.
      ls_act-datum   = ls_job-strtdate.
      ls_act-uzeit   = ls_job-strttime.
      ls_act-source  = 'ARKA PLAN JOB'.
      ls_act-prog_name = ls_job-progname.
      ls_act-object  = |{ ls_job-jobname } / { ls_job-jobcount }|.
      ls_act-action  = 'Kullanıcı adına job adımı çalıştı'.
      ls_act-text    = |Planlayan: { ls_job-sdluname } |
                    && |Varyant: { ls_job-variant } |
                    && |Durum: { ls_job-status }|.
      APPEND ls_act TO ct_act.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------
* 5) Transport talepleri (oluşturduğu/değiştirdiği/serbest bıraktığı)
*----------------------------------------------------------------------
  METHOD read_transports.
    TYPES: BEGIN OF ty_tr,
             trkorr     TYPE e070-trkorr,
             trfunction TYPE e070-trfunction,
             trstatus   TYPE e070-trstatus,
             as4date    TYPE e070-as4date,
             as4time    TYPE e070-as4time,
           END OF ty_tr.
    DATA: lt_tr   TYPE STANDARD TABLE OF ty_tr,
          ls_tr   TYPE ty_tr,
          lv_text TYPE e07t-as4text,
          lv_fd   TYPE sydatum,
          lv_td   TYPE sydatum,
          lv_t    TYPE syuzeit,
          ls_act  TYPE zby_hareket.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_t ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_t ).

    SELECT trkorr trfunction trstatus as4date as4time
      FROM e070 INTO TABLE lt_tr
      WHERE as4user = iv_bname
        AND as4date BETWEEN lv_fd AND lv_td.

    LOOP AT lt_tr INTO ls_tr.
      CHECK in_window( iv_date = ls_tr-as4date iv_time = ls_tr-as4time
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR lv_text.
      SELECT SINGLE as4text FROM e07t INTO lv_text
        WHERE trkorr = ls_tr-trkorr AND langu = sy-langu.
      CLEAR ls_act.
      ls_act-datum  = ls_tr-as4date.
      ls_act-uzeit  = ls_tr-as4time.
      ls_act-source = 'TRANSPORT'.
      ls_act-object = ls_tr-trkorr.
      ls_act-action = |Transport (tip { ls_tr-trfunction }, |
                   && |durum { ls_tr-trstatus }) |
                   && |oluşturuldu/değiştirildi|.
      ls_act-text   = lv_text.
      APPEND ls_act TO ct_act.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------
* 6) SE16N ile yapılan tablo değişiklikleri (RKSE16N_CD_DISPLAY
*    kaynağı: SE16N_CD_KEY / SE16N_CD_DATA)
*----------------------------------------------------------------------
  METHOD read_se16n.
    DATA: lt_key  TYPE STANDARD TABLE OF se16n_cd_key,
          ls_key  TYPE se16n_cd_key,
          lt_data TYPE STANDARD TABLE OF se16n_cd_data,
          ls_data TYPE se16n_cd_data,
          lv_fd   TYPE sydatum,
          lv_td   TYPE sydatum,
          lv_t    TYPE syuzeit,
          lv_any  TYPE abap_bool,
          ls_act  TYPE zby_hareket.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_t ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_t ).

    SELECT * FROM se16n_cd_key INTO TABLE lt_key
      WHERE uname = iv_bname
        AND sdate BETWEEN lv_fd AND lv_td.              "#EC CI_NOFIELD
    LOOP AT lt_key INTO ls_key.
      IF in_window( iv_date = ls_key-sdate iv_time = ls_key-stime
                    iv_from = iv_from iv_to = iv_to ) = abap_false.
        DELETE lt_key.
      ENDIF.
    ENDLOOP.
    CHECK lt_key IS NOT INITIAL.

    SELECT * FROM se16n_cd_data INTO TABLE lt_data
      FOR ALL ENTRIES IN lt_key
      WHERE id = lt_key-id.

    LOOP AT lt_key INTO ls_key.
      lv_any = abap_false.
      LOOP AT lt_data INTO ls_data WHERE id = ls_key-id.
        lv_any = abap_true.
        CLEAR ls_act.
        ls_act-datum  = ls_key-sdate.
        ls_act-uzeit  = ls_key-stime.
        ls_act-source = 'SE16N'.
        ls_act-tcode  = 'SE16N'.
        ls_act-object = ls_data-tab.
        ls_act-action = SWITCH #( ls_data-change_type
                          WHEN 'I' THEN 'SE16N: kayıt eklendi'
                          WHEN 'M' THEN 'SE16N: kayıt değiştirildi'
                          WHEN 'D' THEN 'SE16N: kayıt silindi'
                          ELSE |SE16N: işlem { ls_data-change_type }| ).
        IF ls_data-change_type = 'D'.
          ls_act-old_value = rec_text( iv_tab   = ls_data-tab
                                       iv_value = ls_data-value ).
        ELSE.
          ls_act-new_value = rec_text( iv_tab   = ls_data-tab
                                       iv_value = ls_data-value ).
        ENDIF.
        ls_act-text = 'Detay: RKSE16N_CD_DISPLAY'.
        APPEND ls_act TO ct_act.
      ENDLOOP.
      IF lv_any = abap_false.
        CLEAR ls_act.
        ls_act-datum  = ls_key-sdate.
        ls_act-uzeit  = ls_key-stime.
        ls_act-source = 'SE16N'.
        ls_act-tcode  = 'SE16N'.
        ls_act-object = ls_key-tab.
        ls_act-action = 'SE16N ile tablo değişikliği'.
        ls_act-text   = 'Detay: RKSE16N_CD_DISPLAY'.
        APPEND ls_act TO ct_act.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD rec_text.
*   SE16N ham kaydını tablo alanlarına ayırıp "ALAN=değer" metnine
*   çevirir (RKSE16N_CD_DISPLAY ile aynı yöntem)
    DATA: lr_rec  TYPE REF TO data,
          lo_str  TYPE REF TO cl_abap_structdescr,
          lt_fld  TYPE ddfields,
          ls_fld  TYPE dfies,
          lv_c    TYPE c LENGTH 60.
    FIELD-SYMBOLS: <ls_rec> TYPE any,
                   <lx_rec> TYPE x,
                   <lx_val> TYPE x,
                   <lv_f>   TYPE any.

    TRY.
        CREATE DATA lr_rec TYPE (iv_tab).
        ASSIGN lr_rec->* TO <ls_rec>.
        ASSIGN <ls_rec> TO <lx_rec> CASTING.
        ASSIGN iv_value TO <lx_val> CASTING.
        <lx_rec> = <lx_val>.
        lo_str ?= cl_abap_typedescr=>describe_by_data( <ls_rec> ).
        lt_fld = lo_str->get_ddic_field_list( ).
      CATCH cx_root.
        rv = iv_value.
        RETURN.
    ENDTRY.

    LOOP AT lt_fld INTO ls_fld.
      CHECK ls_fld-datatype <> 'CLNT'.
      ASSIGN COMPONENT ls_fld-fieldname OF STRUCTURE <ls_rec>
        TO <lv_f>.
      CHECK sy-subrc = 0.
      WRITE <lv_f> TO lv_c LEFT-JUSTIFIED.
      CHECK lv_c IS NOT INITIAL.
      rv = |{ rv }{ ls_fld-fieldname }={ lv_c } |.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------
* 7) Security Audit Log (SM20 / RSAU_SELECT_EVENTS) – rapor arka
*    planda çalıştırılır, ALV verisi yakalanır
*----------------------------------------------------------------------
  METHOD read_audit.
    DATA: lr_user   TYPE RANGE OF rsauentr-slguser,
          ls_user   LIKE LINE OF lr_user,
          lr_client TYPE RANGE OF rsauentr-slgmand,
          ls_client LIKE LINE OF lr_client,
          lr_data   TYPE REF TO data,
          lv_fd     TYPE sydatum,
          lv_ft     TYPE syuzeit,
          lv_td     TYPE sydatum,
          lv_tt     TYPE syuzeit,
          lv_date   TYPE sydatum,
          lv_time   TYPE syuzeit,
          lv_class  TYPE string,
          lv_sev    TYPE string,
          ls_act    TYPE zby_hareket.
    FIELD-SYMBOLS: <lt_out> TYPE STANDARD TABLE,
                   <ls_out> TYPE any.

*   RSAU_SELECT_EVENTS ile aynı yetki kontrolü
    AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
      ID 'S_ADMI_FCD' FIELD 'AUDD'.
    IF sy-subrc <> 0.
      APPEND 'Audit log okunamadı: S_ADMI_FCD (AUDD) yetkisi yok' TO
        ct_msg.
      RETURN.
    ENDIF.

    lcl_db=>split_ts( EXPORTING iv_ts = iv_from
                      IMPORTING ev_date = lv_fd ev_time = lv_ft ).
    lcl_db=>split_ts( EXPORTING iv_ts = iv_to
                      IMPORTING ev_date = lv_td ev_time = lv_tt ).

    ls_user-sign   = 'I'.
    ls_user-option = 'EQ'.
    ls_user-low    = iv_bname.
    APPEND ls_user TO lr_user.
    ls_client-sign   = 'I'.
    ls_client-option = 'EQ'.
    ls_client-low    = sy-mandt.
    APPEND ls_client TO lr_client.

*   ALV ekrana basılmaz, yalnızca veri alınır
    cl_salv_bs_runtime_info=>set( display  = abap_false
                                  metadata = abap_false
                                  data     = abap_true ).
    SUBMIT rsau_select_events
      WITH strtdate = lv_fd
      WITH strttime = lv_ft
      WITH enddate  = lv_td
      WITH endtime  = lv_tt
      WITH user     IN lr_user
      WITH client   IN lr_client
      WITH s_alvgrd = abap_true
      EXPORTING LIST TO MEMORY
      AND RETURN.

    TRY.
        cl_salv_bs_runtime_info=>get_data_ref(
          IMPORTING r_data = lr_data ).
      CATCH cx_salv_bs_sc_runtime_info.
        CLEAR lr_data.
    ENDTRY.
    cl_salv_bs_runtime_info=>clear_all( ).
    CALL FUNCTION 'LIST_FREE_MEMORY'.

    IF lr_data IS NOT BOUND.
      APPEND 'Audit log: kayıt yok veya RSAU_SELECT_EVENTS sonucu '
           & 'alınamadı' TO ct_msg.
      RETURN.
    ENDIF.
    ASSIGN lr_data->* TO <lt_out>.

    LOOP AT <lt_out> ASSIGNING <ls_out>.
      CHECK comp( is_rec = <ls_out> iv_name = 'ALGUSER' ) = iv_bname.
      lv_date = comp( is_rec = <ls_out> iv_name = 'ALGDATE' ).
      lv_time = comp( is_rec = <ls_out> iv_name = 'ALGTIME' ).
      CHECK in_window( iv_date = lv_date iv_time = lv_time
                       iv_from = iv_from iv_to = iv_to ) = abap_true.
      CLEAR ls_act.
      ls_act-datum     = lv_date.
      ls_act-uzeit     = lv_time.
      ls_act-source    = 'AUDIT LOG'.
      ls_act-tcode     = comp( is_rec = <ls_out> iv_name = 'ALGTCODE' ).
      ls_act-prog_name = comp( is_rec = <ls_out> iv_name = 'ALGREPNA' ).
      ls_act-terminal  = comp( is_rec = <ls_out> iv_name = 'ALGLTERM' ).
      ls_act-object    = |Olay |
                      && comp( is_rec = <ls_out> iv_name = 'ALGAREA' )
                      && comp( is_rec = <ls_out> iv_name = 'ALGSUBID' ).
      lv_class = comp( is_rec = <ls_out> iv_name = 'TXSUBCLSID' ).
      lv_sev   = comp( is_rec = <ls_out> iv_name = 'TXSEVERITY' ).
      ls_act-action = |{ lv_class } ({ lv_sev })|.
      ls_act-text = comp( is_rec = <ls_out> iv_name = 'ALGSTRING' ).
      IF ls_act-text IS INITIAL.
        ls_act-text = comp( is_rec = <ls_out> iv_name = 'ALGTEXT' ).
      ENDIF.
      APPEND ls_act TO ct_act.
    ENDLOOP.
  ENDMETHOD.

  METHOD comp.
    FIELD-SYMBOLS <lv_f> TYPE any.

    ASSIGN COMPONENT iv_name OF STRUCTURE is_rec TO <lv_f>.
    IF sy-subrc = 0.
      rv = <lv_f>.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Uygulama
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS create_request.
    METHODS show_list
      IMPORTING iv_mode TYPE c.
    METHODS run_job
      IMPORTING iv_test TYPE abap_bool.

  PRIVATE SECTION.
    DATA: mv_mode TYPE c,
          mt_list TYPE ty_t_list,
          mo_alv  TYPE REF TO cl_salv_table.

*   Süreç adımları
    METHODS approve        CHANGING cs_row TYPE ty_list.
    METHODS reject         CHANGING cs_row TYPE ty_list.
    METHODS grant          CHANGING cs_row TYPE ty_list.
    METHODS end_or_cancel  CHANGING cs_row TYPE ty_list.
    METHODS activate
      EXPORTING ev_ok  TYPE abap_bool
      CHANGING  cs_req TYPE zby_talep.
    METHODS end_access
      IMPORTING iv_status TYPE zby_talep-status
      EXPORTING ev_ok     TYPE abap_bool
      CHANGING  cs_req    TYPE zby_talep.
    METHODS collect_and_store
      IMPORTING iv_upto TYPE timestamp
      CHANGING  cs_req  TYPE zby_talep.
    METHODS show_report
      IMPORTING is_req TYPE zby_talep.
    METHODS summary_lines
      IMPORTING iv_req_id TYPE zby_talep-req_id
      CHANGING  ct_body   TYPE soli_tab.

*   Yardımcılar
    METHODS reread          CHANGING cs_row TYPE ty_list.
    METHODS decorate        CHANGING cs_row TYPE ty_list.
    METHODS can_view
      IMPORTING is_req    TYPE zby_talep
      RETURNING VALUE(rv) TYPE abap_bool.
    METHODS ask_note
      IMPORTING iv_title     TYPE csequence
                iv_mandatory TYPE abap_bool
      EXPORTING ev_cancel    TYPE abap_bool
                ev_note      TYPE text255.
    METHODS confirm
      IMPORTING iv_question TYPE csequence
      RETURNING VALUE(rv)   TYPE abap_bool.
    METHODS notify
      IMPORTING it_rcpt    TYPE ty_t_rcpt
                is_req     TYPE zby_talep
                iv_subject TYPE csequence
                iv_intro   TYPE csequence
                iv_action  TYPE csequence OPTIONAL
                iv_summary TYPE abap_bool DEFAULT abap_false.
    METHODS rcpt_requester
      IMPORTING is_req    TYPE zby_talep
      RETURNING VALUE(rt) TYPE ty_t_rcpt.
    METHODS set_column
      IMPORTING io_cols    TYPE REF TO cl_salv_columns_table
                iv_name    TYPE lvc_fname
                iv_text    TYPE csequence OPTIONAL
                iv_hotspot TYPE abap_bool DEFAULT abap_false
                iv_hide    TYPE abap_bool DEFAULT abap_false.
    METHODS on_link_click FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

*======================================================================*
* 1) TALEP
*======================================================================*
  METHOD create_request.
    DATA: ls_req   TYPE zby_talep,
          lv_from  TYPE timestamp,
          lv_to    TYPE timestamp,
          lv_hours TYPE i,
          lv_open  TYPE zby_talep-req_id,
          lt_rcpt  TYPE ty_t_rcpt,
          lv_msg   TYPE string.

    IF p_reas1 IS INITIAL.
      MESSAGE 'Gerekçe zorunludur' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    lv_from = lcl_db=>to_ts( iv_date = p_frd iv_time = p_frt ).
    lv_to   = lcl_db=>to_ts( iv_date = p_tod iv_time = p_tot ).
    IF lv_to <= lv_from.
      MESSAGE 'Bitiş zamanı başlangıçtan sonra olmalıdır' TYPE 'S'
        DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF lv_to <= lcl_db=>now_ts( ).
      MESSAGE 'Bitiş zamanı geçmişte olamaz' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    lv_hours = lcl_cfg=>max_hours( ).
    IF lcl_db=>diff_secs( iv_ts_to = lv_to
                          iv_ts_from = lv_from ) > lv_hours * 3600.
      lv_msg = |En fazla { lv_hours } saatlik yetki talep edilebilir|.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    lt_rcpt = lcl_cfg=>users( gc_utype-approver ).
    IF lt_rcpt IS INITIAL.
      MESSAGE
        'ZBY_KULLANICI tablosunda aktif onaycı tanımlı değil' TYPE 'S'
        DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

*   Aynı kullanıcı için açık talep var mı?
    SELECT SINGLE req_id FROM zby_talep INTO lv_open
      WHERE bname = sy-uname
        AND ( status = gc_st-pending OR status = gc_st-approved
           OR status = gc_st-planned OR status = gc_st-active ).
    IF sy-subrc = 0.
      lv_msg = |Açık talebiniz var: { lv_open ALPHA = OUT } |
            && |(Taleplerim ekranından izleyin)|.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    ls_req-req_id        = lcl_db=>next_id( ).
    ls_req-bname         = sy-uname.
    ls_req-agr_name      = lcl_cfg=>role( ).
    ls_req-req_from_date = p_frd.
    ls_req-req_from_time = p_frt.
    ls_req-req_to_date   = p_tod.
    ls_req-req_to_time   = p_tot.
*   Ticket / olay no: talep numarasıyla aynı sıralı numara
    ls_req-ticket        = |{ ls_req-req_id ALPHA = OUT }|.
    ls_req-reason        = |{ p_reas1 } { p_reas2 }|.
    ls_req-status        = gc_st-pending.
    ls_req-cr_date       = sy-datum.
    ls_req-cr_time       = sy-uzeit.
    INSERT zby_talep FROM ls_req.

    lcl_db=>log( iv_id = ls_req-req_id iv_action = 'TALEP'
                 iv_msg = ls_req-reason ).

    notify( it_rcpt    = lt_rcpt
            is_req     = ls_req
            iv_subject = |Yetki talebi { ls_req-req_id ALPHA = OUT } |
                      && |onayınızı bekliyor ({ sy-uname })|
            iv_intro   = 'Onayınızı bekleyen bir süreli yetki '
                       & 'talebi var.'
            iv_action  = 'Onaylamak / reddetmek için ZBY_ONAY işlem '
                       & 'kodunu kullanın.' ).
    COMMIT WORK.

    lv_msg = |Talep { ls_req-req_id ALPHA = OUT } oluşturuldu ve |
          && |onaycılara gönderildi|.
    MESSAGE lv_msg TYPE 'S'.
  ENDMETHOD.

*======================================================================*
* LİSTE (Taleplerim / Onay / Basis / Rapor)
*======================================================================*
  METHOD show_list.
    DATA: lt_req  TYPE ty_t_talep,
          ls_req  TYPE zby_talep,
          ls_row  TYPE ty_list,
          lr_stat TYPE RANGE OF zby_talep-status,
          lo_cols TYPE REF TO cl_salv_columns_table,
          lo_evt  TYPE REF TO cl_salv_events_table,
          lv_head TYPE lvc_title,
          lx_salv TYPE REF TO cx_salv_msg.

    mv_mode = iv_mode.

    CASE iv_mode.
      WHEN gc_mode-approve.
        IF lcl_cfg=>is_user( gc_utype-approver ) = abap_false.
          MESSAGE 'ZBY_KULLANICI tablosunda onaycı olarak '
                & 'tanımlı değilsiniz' TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        lr_stat = VALUE #( ( sign = 'I' option = 'EQ'
                           low = gc_st-pending ) ).
      WHEN gc_mode-basis.
        IF lcl_cfg=>is_user( gc_utype-basis ) = abap_false.
          MESSAGE 'ZBY_KULLANICI tablosunda Basis olarak '
                & 'tanımlı değilsiniz' TYPE 'S' DISPLAY LIKE 'E'.
          RETURN.
        ENDIF.
        IF s_stat[] IS INITIAL.
          lr_stat = VALUE #( ( sign = 'I' option = 'EQ'
                             low = gc_st-approved )
                             ( sign = 'I' option = 'EQ'
                             low = gc_st-planned )
                             ( sign = 'I' option = 'EQ'
                             low = gc_st-active ) ).
        ELSE.
          lr_stat = s_stat[].
        ENDIF.
      WHEN OTHERS.
        lr_stat = s_stat[].
    ENDCASE.

    SELECT * FROM zby_talep INTO TABLE lt_req
      WHERE req_id  IN s_reqid
        AND bname   IN s_bname
        AND status  IN lr_stat
        AND cr_date IN s_crdat.

    CLEAR mt_list.
    LOOP AT lt_req INTO ls_req.
      IF iv_mode = gc_mode-my.
        CHECK ls_req-bname = sy-uname.
      ELSEIF iv_mode = gc_mode-report.
        CHECK can_view( ls_req ) = abap_true.
      ENDIF.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_req TO ls_row.
      decorate( CHANGING cs_row = ls_row ).
      APPEND ls_row TO mt_list.
    ENDLOOP.

    IF mt_list IS INITIAL.
      MESSAGE 'Görüntülenecek talep yok' TYPE 'S'.
      RETURN.
    ENDIF.
    SORT mt_list BY req_id DESCENDING.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_alv
                                CHANGING  t_table      = mt_list ).
      CATCH cx_salv_msg INTO lx_salv.
        MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    lv_head = SWITCH #( iv_mode
                WHEN gc_mode-my      THEN 'Yetki taleplerim'
                WHEN gc_mode-approve
                THEN 'Onayımı bekleyen yetki talepleri'
                WHEN gc_mode-basis
                THEN 'Basis – yetki tanımlama ve yönetim'
                ELSE 'Yetki talepleri ve kullanıcı hareket raporu' ).
    mo_alv->get_display_settings( )->set_list_header( lv_head ).
    mo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    mo_alv->get_functions( )->set_all( abap_true ).

    lo_cols = mo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).
    set_column( io_cols = lo_cols iv_name = 'MANDT'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'STATUS'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'COLLECTED_TS'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'STATUS_TXT'
                iv_text = 'Durum' ).
    set_column( io_cols = lo_cols iv_name = 'I_APPROVE'
                iv_text = 'Onayla' iv_hotspot = abap_true
                iv_hide = xsdbool( iv_mode <> gc_mode-approve ) ).
    set_column( io_cols = lo_cols iv_name = 'I_REJECT'
                iv_text = 'Reddet' iv_hotspot = abap_true
                iv_hide = xsdbool( iv_mode <> gc_mode-approve AND
                                   iv_mode <> gc_mode-basis ) ).
    set_column( io_cols = lo_cols iv_name = 'I_GRANT'
                iv_text = 'Yetki tanımla' iv_hotspot = abap_true
                iv_hide = xsdbool( iv_mode <> gc_mode-basis ) ).
    set_column( io_cols = lo_cols iv_name = 'I_END'
                iv_text = 'Tamamla/İptal' iv_hotspot = abap_true
                iv_hide = xsdbool( iv_mode <> gc_mode-my AND
                                   iv_mode <> gc_mode-basis ) ).
    set_column( io_cols = lo_cols iv_name = 'I_REPORT'
                iv_text = 'Hareket raporu' iv_hotspot = abap_true ).

    lo_evt = mo_alv->get_event( ).
    SET HANDLER on_link_click FOR lo_evt.
    mo_alv->display( ).
  ENDMETHOD.

  METHOD decorate.
    DATA ls_req TYPE zby_talep.

    MOVE-CORRESPONDING cs_row TO ls_req.
    cs_row-status_txt = lcl_db=>status_text( cs_row-status ).
    CLEAR: cs_row-i_approve, cs_row-i_reject, cs_row-i_grant,
           cs_row-i_end, cs_row-i_report.

    CASE mv_mode.
      WHEN gc_mode-approve.
        IF cs_row-status = gc_st-pending.
          cs_row-i_approve = icon_okay.
          cs_row-i_reject  = icon_cancel.
        ENDIF.

      WHEN gc_mode-basis.
        CASE cs_row-status.
          WHEN gc_st-approved.
            cs_row-i_grant  = icon_change_text.
            cs_row-i_reject = icon_cancel.
          WHEN gc_st-planned OR gc_st-active.
            " erken sonlandır
            cs_row-i_end = icon_led_red.
        ENDCASE.

      WHEN gc_mode-my.
        CASE cs_row-status.
          WHEN gc_st-pending OR gc_st-approved OR gc_st-planned.
            " talebi iptal et
            cs_row-i_end = icon_delete.
          WHEN gc_st-active.
            " süreci tamamla
            cs_row-i_end = icon_complete.
        ENDCASE.
    ENDCASE.

    IF ( cs_row-status = gc_st-active OR
         cs_row-status = gc_st-completed OR
         cs_row-status = gc_st-expired OR
         cs_row-status = gc_st-stopped ) AND
       can_view( ls_req ) = abap_true.
      cs_row-i_report = icon_report.
    ENDIF.
  ENDMETHOD.

  METHOD can_view.
    rv = xsdbool( is_req-bname = sy-uname OR
                  lcl_cfg=>is_privileged( ) = abap_true ).
  ENDMETHOD.

  METHOD on_link_click.
    FIELD-SYMBOLS <ls_row> TYPE ty_list.
    DATA ls_req TYPE zby_talep.

    READ TABLE mt_list ASSIGNING <ls_row> INDEX row.
    CHECK sy-subrc = 0.

    CASE column.
      WHEN 'I_APPROVE'.
        CHECK <ls_row>-i_approve IS NOT INITIAL.
        approve( CHANGING cs_row = <ls_row> ).
      WHEN 'I_REJECT'.
        CHECK <ls_row>-i_reject IS NOT INITIAL.
        reject( CHANGING cs_row = <ls_row> ).
      WHEN 'I_GRANT'.
        CHECK <ls_row>-i_grant IS NOT INITIAL.
        grant( CHANGING cs_row = <ls_row> ).
      WHEN 'I_END'.
        CHECK <ls_row>-i_end IS NOT INITIAL.
        end_or_cancel( CHANGING cs_row = <ls_row> ).
      WHEN 'I_REPORT'.
        CHECK <ls_row>-i_report IS NOT INITIAL.
        MOVE-CORRESPONDING <ls_row> TO ls_req.
        show_report( ls_req ).
        reread( CHANGING cs_row = <ls_row> ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    decorate( CHANGING cs_row = <ls_row> ).
    mo_alv->refresh( ).
  ENDMETHOD.

  METHOD reread.
    DATA ls_req TYPE zby_talep.

    SELECT SINGLE * FROM zby_talep INTO ls_req WHERE
      req_id = cs_row-req_id.
    IF sy-subrc = 0.
      MOVE-CORRESPONDING ls_req TO cs_row.
    ENDIF.
  ENDMETHOD.

*======================================================================*
* 2) ONAY / RED
*======================================================================*
  METHOD approve.
    DATA: ls_req    TYPE zby_talep,
          lv_note   TYPE text255,
          lv_cancel TYPE abap_bool.

    reread( CHANGING cs_row = cs_row ).
    IF cs_row-status <> gc_st-pending.
      MESSAGE 'Talep artık onay beklemiyor' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.
    IF lcl_cfg=>is_user( gc_utype-approver ) = abap_false.
      MESSAGE 'Onay yetkiniz yok' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF cs_row-bname = sy-uname.
      MESSAGE
        'Kendi talebinizi onaylayamazsınız (4 göz ilkesi)' TYPE 'S'
        DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    ask_note( EXPORTING iv_title = 'Onay notu (opsiyonel)'
              iv_mandatory = abap_false
              IMPORTING ev_cancel = lv_cancel ev_note = lv_note ).
    CHECK lv_cancel = abap_false.

    MOVE-CORRESPONDING cs_row TO ls_req.
    ls_req-status    = gc_st-approved.
    ls_req-approver  = sy-uname.
    ls_req-appr_date = sy-datum.
    ls_req-appr_time = sy-uzeit.
    ls_req-appr_note = lv_note.
    UPDATE zby_talep FROM ls_req.
    lcl_db=>log( iv_id = ls_req-req_id iv_action = 'ONAY'
                 iv_msg = lv_note ).

*   Basis ekibine yetki tanımlama talebi, kullanıcıya bilgi
    notify( it_rcpt    = lcl_cfg=>users( gc_utype-basis )
            is_req     = ls_req
            iv_subject = |Yetki talebi { ls_req-req_id ALPHA = OUT } |
                      && |onaylandı – tanımlama bekliyor|
            iv_intro   = 'Aşağıdaki yetki talebi onaylandı. Lütfen '
                       & 'tarih/saat aralığını belirleyerek tanımlayın.'
            iv_action  = 'Tanımlamak için ZBY_BASIS işlem kodunu '
                       & 'kullanın.' ).
    notify( it_rcpt    = rcpt_requester( ls_req )
            is_req     = ls_req
            iv_subject = |Yetki talebiniz |
                      && |{ ls_req-req_id ALPHA = OUT } onaylandı|
            iv_intro   = 'Yetki talebiniz onaylandı, Basis ekibinin '
                       & 'tanımlaması bekleniyor.' ).
    COMMIT WORK.

    MOVE-CORRESPONDING ls_req TO cs_row.
    MESSAGE 'Talep onaylandı, Basis ekibine iletildi' TYPE 'S'.
  ENDMETHOD.

  METHOD reject.
    DATA: ls_req    TYPE zby_talep,
          lv_note   TYPE text255,
          lv_cancel TYPE abap_bool.

    reread( CHANGING cs_row = cs_row ).
    IF NOT ( ( mv_mode = gc_mode-approve AND
               cs_row-status = gc_st-pending AND
               lcl_cfg=>is_user( gc_utype-approver ) = abap_true ) OR
             ( mv_mode = gc_mode-basis AND
               cs_row-status = gc_st-approved AND
               lcl_cfg=>is_user( gc_utype-basis ) = abap_true ) ).
      MESSAGE 'Bu talep bu aşamada reddedilemez' TYPE 'S'
        DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    ask_note( EXPORTING iv_title = 'Red gerekçesi (zorunlu)'
              iv_mandatory = abap_true
              IMPORTING ev_cancel = lv_cancel ev_note = lv_note ).
    CHECK lv_cancel = abap_false.

    MOVE-CORRESPONDING cs_row TO ls_req.
    ls_req-status = gc_st-rejected.
    IF mv_mode = gc_mode-approve.
      ls_req-approver  = sy-uname.
      ls_req-appr_date = sy-datum.
      ls_req-appr_time = sy-uzeit.
      ls_req-appr_note = lv_note.
    ELSE.
      ls_req-basis_user = sy-uname.
      ls_req-basis_date = sy-datum.
      ls_req-basis_time = sy-uzeit.
      ls_req-basis_note = lv_note.
    ENDIF.
    UPDATE zby_talep FROM ls_req.
    lcl_db=>log( iv_id = ls_req-req_id iv_action = 'RED'
                 iv_msg = lv_note ).

    notify( it_rcpt    = rcpt_requester( ls_req )
            is_req     = ls_req
            iv_subject = |Yetki talebiniz |
                      && |{ ls_req-req_id ALPHA = OUT } reddedildi|
            iv_intro   = 'Yetki talebiniz reddedildi.'
            iv_action  = |Gerekçe: { lv_note }| ).
    COMMIT WORK.

    MOVE-CORRESPONDING ls_req TO cs_row.
    MESSAGE 'Talep reddedildi' TYPE 'S'.
  ENDMETHOD.

*======================================================================*
* 3) BASIS – tarih/saat aralığı ile yetki tanımlama
*======================================================================*
  METHOD grant.
    DATA: ls_req   TYPE zby_talep,
          lv_from  TYPE timestamp,
          lv_to    TYPE timestamp,
          lv_hours TYPE i,
          lv_ok    TYPE abap_bool,
          lv_msg   TYPE string.

    reread( CHANGING cs_row = cs_row ).
    IF cs_row-status <> gc_st-approved.
      MESSAGE 'Talep tanımlama aşamasında değil' TYPE 'S'
        DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.
    IF lcl_cfg=>is_user( gc_utype-basis ) = abap_false.
      MESSAGE 'Basis yetkiniz yok' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF cs_row-bname = sy-uname.
      MESSAGE
        'Kendinize yetki tanımlayamazsınız (4 göz ilkesi)' TYPE 'S'
        DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

*   Popup varsayılanları: talep edilen aralık
    p_grole = cs_row-agr_name.
    p_gfd   = cs_row-req_from_date.
    p_gft   = cs_row-req_from_time.
    p_gtd   = cs_row-req_to_date.
    p_gtt   = cs_row-req_to_time.
    IF lcl_db=>to_ts( iv_date = p_gfd
                      iv_time = p_gft ) < lcl_db=>now_ts( ).
      p_gfd = sy-datum.
      p_gft = sy-uzeit.
    ENDIF.
    CLEAR p_gnote.

    CALL SELECTION-SCREEN 9100 STARTING AT 10 5.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_from = lcl_db=>to_ts( iv_date = p_gfd iv_time = p_gft ).
    lv_to   = lcl_db=>to_ts( iv_date = p_gtd iv_time = p_gtt ).
    IF lv_to <= lv_from OR lv_to <= lcl_db=>now_ts( ).
      MESSAGE 'Geçersiz aralık: bitiş, başlangıçtan ve şu andan '
            & 'sonra olmalı' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    lv_hours = lcl_cfg=>max_hours( ).
    IF lcl_db=>diff_secs( iv_ts_to = lv_to
                          iv_ts_from = lv_from ) > lv_hours * 3600.
      lv_msg = |En fazla { lv_hours } saat tanımlanabilir |
            && |(ZBY_PARAM-MAKS_SAAT)|.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF lcl_role=>role_exists( p_grole ) = abap_false.
      lv_msg = |Rol { p_grole } sistemde yok|.
      MESSAGE lv_msg TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING cs_row TO ls_req.
    ls_req-agr_name        = p_grole.
    ls_req-valid_from_date = p_gfd.
    ls_req-valid_from_time = p_gft.
    ls_req-valid_to_date   = p_gtd.
    ls_req-valid_to_time   = p_gtt.
    ls_req-basis_user      = sy-uname.
    ls_req-basis_date      = sy-datum.
    ls_req-basis_time      = sy-uzeit.
    ls_req-basis_note      = p_gnote.
    ls_req-status          = gc_st-planned.

    IF lv_from <= lcl_db=>now_ts( ).
*     Başlangıç zamanı geldi: hemen ata
      activate( IMPORTING ev_ok = lv_ok CHANGING cs_req = ls_req ).
      IF lv_ok = abap_false.
        MESSAGE ls_req-last_msg TYPE 'S' DISPLAY LIKE 'E'.
        reread( CHANGING cs_row = cs_row ).
        RETURN.
      ENDIF.
      lv_msg = |Yetki tanımlandı ve aktif: |
            && lcl_db=>ts_text( iv_date = p_gtd iv_time = p_gtt )
            && | saatine kadar|.
    ELSE.
*     İleri tarihli: job başlangıçta atar
      UPDATE zby_talep FROM ls_req.
      lcl_db=>log( iv_id = ls_req-req_id iv_action = 'PLANLANDI'
                   iv_msg = |{ p_grole } |
                         && lcl_db=>ts_text( iv_date = p_gfd
                                             iv_time = p_gft )
                         && | - |
                         && lcl_db=>ts_text( iv_date = p_gtd
                                             iv_time = p_gtt ) ).
      notify( it_rcpt    = rcpt_requester( ls_req )
              is_req     = ls_req
              iv_subject = |Yetkiniz { ls_req-req_id ALPHA = OUT } |
                        && |planlandı|
              iv_intro   = 'Yetkiniz Basis tarafından tanımlandı ve '
                         & 'başlangıç zamanında otomatik aktif '
                         & 'olacak.' ).
      COMMIT WORK.
      lv_msg = |Yetki planlandı; |
            && lcl_db=>ts_text( iv_date = p_gfd iv_time = p_gft )
            && | saatinde aktif olacak|.
    ENDIF.

    MOVE-CORRESPONDING ls_req TO cs_row.
    MESSAGE lv_msg TYPE 'S'.
  ENDMETHOD.

  METHOD activate.
    DATA: lv_preexist TYPE abap_bool,
          lv_msg      TYPE string.

    CLEAR ev_ok.
    lcl_role=>assign( EXPORTING iv_bname    = cs_req-bname
                                iv_role     = cs_req-agr_name
                                iv_from     = cs_req-valid_from_date
                                iv_to       = cs_req-valid_to_date
                      IMPORTING ev_preexist = lv_preexist
                                ev_ok       = ev_ok
                                ev_msg      = lv_msg ).
    cs_req-last_msg = lv_msg.
    IF ev_ok = abap_false.
      lcl_db=>log( iv_id = cs_req-req_id iv_action = 'ATAMA_HATA'
                   iv_msg = lv_msg ).
      UPDATE zby_talep SET last_msg = cs_req-last_msg WHERE
        req_id = cs_req-req_id.
      COMMIT WORK.
      RETURN.
    ENDIF.

    cs_req-role_preexist = lv_preexist.
    cs_req-role_assigned = xsdbool( lv_preexist = abap_false ).
    cs_req-status        = gc_st-active.
    CLEAR cs_req-collected_ts.
    UPDATE zby_talep FROM cs_req.
    lcl_db=>log( iv_id = cs_req-req_id iv_action = 'AKTIF'
                 iv_msg = lv_msg ).

    notify( it_rcpt    = rcpt_requester( cs_req )
            is_req     = cs_req
            iv_subject = |Yetkiniz { cs_req-req_id ALPHA = OUT } aktif|
            iv_intro   = 'Süreli yetkiniz aktif edildi. Bu süre '
                       & 'içindeki tüm işlemleriniz raporlanacaktır.'
            iv_action  = 'İşiniz bitince ZBY_TALEP > Taleplerim '
                       & 'ekranından "Süreci tamamla" seçin.' ).
    COMMIT WORK.
  ENDMETHOD.

*======================================================================*
* 4) BİTİŞ – kullanıcı tamamlar / Basis sonlandırır / süre dolar
*======================================================================*
  METHOD end_or_cancel.
    DATA: ls_req TYPE zby_talep,
          lv_ok  TYPE abap_bool,
          lv_new TYPE zby_talep-status.

    reread( CHANGING cs_row = cs_row ).
    MOVE-CORRESPONDING cs_row TO ls_req.

    CASE ls_req-status.
      WHEN gc_st-pending OR gc_st-approved OR gc_st-planned.
        IF mv_mode = gc_mode-my AND ls_req-bname = sy-uname.
          CHECK confirm( 'Talebiniz iptal edilsin mi?' ) = abap_true.
          ls_req-status     = gc_st-cancelled.
          ls_req-ended_by   = sy-uname.
          ls_req-ended_date = sy-datum.
          ls_req-ended_time = sy-uzeit.
          UPDATE zby_talep FROM ls_req.
          lcl_db=>log( iv_id = ls_req-req_id iv_action = 'IPTAL'
                       iv_msg = 'Kullanıcı iptal etti' ).
          COMMIT WORK.
          MESSAGE 'Talep iptal edildi' TYPE 'S'.
        ELSEIF mv_mode = gc_mode-basis AND
               ls_req-status = gc_st-planned.
          CHECK confirm( 'Planlanan yetki iptal edilsin mi?' )
                = abap_true.
          ls_req-status     = gc_st-stopped.
          ls_req-ended_by   = sy-uname.
          ls_req-ended_date = sy-datum.
          ls_req-ended_time = sy-uzeit.
          UPDATE zby_talep FROM ls_req.
          lcl_db=>log(
            iv_id     = ls_req-req_id
            iv_action = 'DURDUR'
            iv_msg    = 'Planlı yetki Basis tarafından iptal edildi' ).
          COMMIT WORK.
          MESSAGE 'Planlanan yetki iptal edildi' TYPE 'S'.
        ENDIF.

      WHEN gc_st-active.
        IF mv_mode = gc_mode-my AND ls_req-bname = sy-uname.
          CHECK confirm( 'İşiniz bitti mi? Yetki geri alınacak ve '
                       & 'işlemleriniz raporlanacak.' ) = abap_true.
          lv_new = gc_st-completed.
        ELSEIF mv_mode = gc_mode-basis AND
               lcl_cfg=>is_user( gc_utype-basis ) = abap_true.
          CHECK confirm( 'Yetki şimdi sonlandırılsın mı?' ) = abap_true.
          lv_new = gc_st-stopped.
        ELSE.
          RETURN.
        ENDIF.
        end_access( EXPORTING iv_status = lv_new IMPORTING ev_ok = lv_ok
                    CHANGING cs_req = ls_req ).
        IF lv_ok = abap_true.
          MESSAGE 'Yetki geri alındı, işlem raporu hazır' TYPE 'S'.
          show_report( ls_req ).
        ELSE.
          MESSAGE ls_req-last_msg TYPE 'S' DISPLAY LIKE 'E'.
        ENDIF.
    ENDCASE.

    reread( CHANGING cs_row = cs_row ).
  ENDMETHOD.

  METHOD end_access.
    DATA: lv_ok    TYPE abap_bool,
          lv_msg   TYPE string,
          lv_end   TYPE timestamp,
          lv_valid TYPE timestamp,
          lt_rcpt  TYPE ty_t_rcpt,
          lt_basis TYPE ty_t_rcpt,
          lv_text  TYPE string.

    CLEAR ev_ok.

*   a) Yetkiyi geri al (önceden mevcut değilse)
    IF cs_req-role_assigned = abap_true.
      lcl_role=>remove( EXPORTING iv_bname = cs_req-bname
                                  iv_role  = cs_req-agr_name
                                  iv_from  = cs_req-valid_from_date
                                  iv_to    = cs_req-valid_to_date
                        IMPORTING ev_ok    = lv_ok
                                  ev_msg   = lv_msg ).
      IF lv_ok = abap_false.
        cs_req-last_msg = |Rol geri alınamadı: { lv_msg }|.
        UPDATE zby_talep SET last_msg = cs_req-last_msg WHERE
          req_id = cs_req-req_id.
        lcl_db=>log( iv_id = cs_req-req_id iv_action = 'GERIALMA_HATA'
                     iv_msg = cs_req-last_msg ).
        COMMIT WORK.
        " job tekrar dener
        RETURN.
      ENDIF.
    ELSE.
      lv_msg = 'Rol önceden mevcuttu, geri alınmadı'.
    ENDIF.

*   b) Hareketlerin son kısmını topla (bitiş = şimdi veya tanımlı bitiş)
    lv_end   = lcl_db=>now_ts( ).
    lv_valid = lcl_db=>to_ts( iv_date = cs_req-valid_to_date
                              iv_time = cs_req-valid_to_time ).
    IF lv_valid < lv_end.
      lv_end = lv_valid.
    ENDIF.
    collect_and_store( EXPORTING iv_upto = lv_end
                       CHANGING cs_req = cs_req ).

*   c) Durum
    cs_req-status     = iv_status.
    cs_req-ended_by   = sy-uname.
    cs_req-ended_date = sy-datum.
    cs_req-ended_time = sy-uzeit.
    cs_req-last_msg   = lv_msg.
    UPDATE zby_talep FROM cs_req.
    lcl_db=>log( iv_id = cs_req-req_id iv_action = 'BITIS'
                 iv_msg = |{ lcl_db=>status_text( iv_status ) }; |
                       && |{ lv_msg }; { cs_req-act_count } hareket| ).

*   d) Rapor özeti: kullanıcı, onaycı ve Basis ekibine
    lt_rcpt = rcpt_requester( cs_req ).
    IF cs_req-approver IS NOT INITIAL.
      APPEND lcl_mail=>user_rcpt( cs_req-approver ) TO lt_rcpt.
    ENDIF.
    lt_basis = lcl_cfg=>users( gc_utype-basis ).
    APPEND LINES OF lt_basis TO lt_rcpt.
    SORT lt_rcpt BY bname.
    DELETE ADJACENT DUPLICATES FROM lt_rcpt COMPARING bname.

    lv_text = |Yetki sona erdi ({ lcl_db=>status_text( iv_status ) }). |
           && |Toplam { cs_req-act_count } hareket kaydedildi.|.
    notify( it_rcpt    = lt_rcpt
            is_req     = cs_req
            iv_subject = |Yetki { cs_req-req_id ALPHA = OUT } |
                      && |sona erdi – işlem raporu|
            iv_intro   = lv_text
            iv_action  = 'Detaylı rapor: ZBY_RAPOR işlem kodu.'
            iv_summary = abap_true ).
    COMMIT WORK.
    ev_ok = abap_true.
  ENDMETHOD.

*======================================================================*
* HAREKET TOPLAMA (artımlı) ve RAPOR
*======================================================================*
  METHOD collect_and_store.
    DATA: lv_from TYPE timestamp,
          lt_act  TYPE ty_t_act,
          lt_msg  TYPE string_table,
          lv_msg  TYPE string,
          lv_seq  TYPE zby_hareket-seq.

    FIELD-SYMBOLS <ls_act> TYPE zby_hareket.

    IF cs_req-collected_ts IS NOT INITIAL.
      lv_from = cs_req-collected_ts.
    ELSE.
      lv_from = lcl_db=>to_ts( iv_date = cs_req-valid_from_date
                               iv_time = cs_req-valid_from_time ).
    ENDIF.
    CHECK lv_from < iv_upto.

    lcl_collector=>collect( EXPORTING iv_bname = cs_req-bname
                                      iv_from  = lv_from
                                      iv_to    = iv_upto
                            IMPORTING et_act   = lt_act
                                      et_msg   = lt_msg ).

    SELECT MAX( seq ) FROM zby_hareket INTO lv_seq WHERE
                req_id = cs_req-req_id.
    LOOP AT lt_act ASSIGNING <ls_act>.
      lv_seq = lv_seq + 1.
      <ls_act>-req_id = cs_req-req_id.
      <ls_act>-seq    = lv_seq.
    ENDLOOP.
    IF lt_act IS NOT INITIAL.
      INSERT zby_hareket FROM TABLE lt_act ACCEPTING DUPLICATE KEYS.
    ENDIF.

    LOOP AT lt_msg INTO lv_msg.
      lcl_db=>log( iv_id = cs_req-req_id iv_action = 'TOPLAMA_UYARI'
                   iv_msg = lv_msg ).
    ENDLOOP.

    cs_req-collected_ts = iv_upto.
    cs_req-act_count    = cs_req-act_count + lines( lt_act ).
    UPDATE zby_talep SET collected_ts = cs_req-collected_ts
                         act_count    = cs_req-act_count
      WHERE req_id = cs_req-req_id.
  ENDMETHOD.

  METHOD show_report.
    DATA: ls_req  TYPE zby_talep,
          lt_act  TYPE ty_t_act,
          lo_alv  TYPE REF TO cl_salv_table,
          lo_cols TYPE REF TO cl_salv_columns_table,
          lo_sort TYPE REF TO cl_salv_sorts,
          lv_head TYPE lvc_title,
          lv_now  TYPE timestamp,
          lv_end  TYPE timestamp,
          lx_salv TYPE REF TO cx_salv_msg.

    SELECT SINGLE * FROM zby_talep INTO ls_req WHERE
      req_id = is_req-req_id.
    CHECK sy-subrc = 0.
    IF can_view( ls_req ) = abap_false.
      MESSAGE 'Bu raporu görüntüleme yetkiniz yok' TYPE 'S'
        DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

*   Yetki hâlâ aktifse rapor anına kadar olan hareketler toplanır
    IF ls_req-status = gc_st-active.
      lv_now = lcl_db=>now_ts( ).
      lv_end = lcl_db=>to_ts( iv_date = ls_req-valid_to_date
                              iv_time = ls_req-valid_to_time ).
      IF lv_end > lv_now.
        lv_end = lv_now.
      ENDIF.
      collect_and_store( EXPORTING iv_upto = lv_end
                         CHANGING cs_req = ls_req ).
      COMMIT WORK.
    ENDIF.

    SELECT * FROM zby_hareket INTO TABLE lt_act WHERE
      req_id = ls_req-req_id.
    IF lt_act IS INITIAL.
      MESSAGE 'Bu yetki süresinde kayıtlı hareket bulunamadı' TYPE 'S'.
      RETURN.
    ENDIF.
    SORT lt_act BY datum uzeit seq.

    lcl_db=>log( iv_id = ls_req-req_id iv_action = 'RAPOR'
                 iv_msg = |{ lines( lt_act ) } hareket görüntülendi| ).
    COMMIT WORK.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv
                                CHANGING  t_table      = lt_act ).
      CATCH cx_salv_msg INTO lx_salv.
        MESSAGE lx_salv TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    lv_head = |{ ls_req-bname } – { ls_req-agr_name } – |
           && lcl_db=>ts_text( iv_date = ls_req-valid_from_date
                               iv_time = ls_req-valid_from_time )
           && | / |
           && lcl_db=>ts_text( iv_date = ls_req-valid_to_date
                               iv_time = ls_req-valid_to_time ).
    lo_alv->get_display_settings( )->set_list_header( lv_head ).
    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->get_functions( )->set_all( abap_true ).

    lo_cols = lo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).
    set_column( io_cols = lo_cols iv_name = 'MANDT'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'REQ_ID'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'SEQ'
                iv_hide = abap_true ).
    set_column( io_cols = lo_cols iv_name = 'DATUM'
                iv_text = 'Tarih' ).
    set_column( io_cols = lo_cols iv_name = 'UZEIT'
                iv_text = 'Saat' ).
    set_column( io_cols = lo_cols iv_name = 'SOURCE'
                iv_text = 'Kaynak' ).
    set_column( io_cols = lo_cols iv_name = 'TCODE'
                iv_text = 'İşlem kodu' ).
    set_column( io_cols = lo_cols iv_name = 'PROG_NAME'
                iv_text = 'Program' ).
    set_column( io_cols = lo_cols iv_name = 'OBJECT'
                iv_text = 'Nesne / Tablo / Anahtar' ).
    set_column( io_cols = lo_cols iv_name = 'ACTION'
                iv_text = 'İşlem' ).
    set_column( io_cols = lo_cols iv_name = 'OLD_VALUE'
                iv_text = 'Eski değer' ).
    set_column( io_cols = lo_cols iv_name = 'NEW_VALUE'
                iv_text = 'Yeni değer' ).
    set_column( io_cols = lo_cols iv_name = 'TEXT'
                iv_text = 'Açıklama' ).
    set_column( io_cols = lo_cols iv_name = 'TERMINAL'
                iv_text = 'Terminal' ).

    lo_sort = lo_alv->get_sorts( ).
    TRY.
        lo_sort->add_sort( columnname = 'DATUM' ).
        lo_sort->add_sort( columnname = 'UZEIT' ).
      CATCH cx_salv_not_found cx_salv_existing cx_salv_data_error.
    ENDTRY.

    lo_alv->display( ).
  ENDMETHOD.

  METHOD summary_lines.
*   E-posta için kaynak bazında özet ve kullanılan işlem kodları
    TYPES: BEGIN OF ty_cnt,
             key TYPE string,
             cnt TYPE i,
           END OF ty_cnt.
    DATA: lt_act TYPE ty_t_act,
          ls_act TYPE zby_hareket,
          lt_src TYPE SORTED TABLE OF ty_cnt WITH UNIQUE KEY key,
          lt_tc  TYPE SORTED TABLE OF ty_cnt WITH UNIQUE KEY key,
          ls_cnt TYPE ty_cnt,
          lv_n   TYPE i.

    FIELD-SYMBOLS <ls_cnt> TYPE ty_cnt.

    SELECT * FROM zby_hareket INTO TABLE lt_act WHERE
      req_id = iv_req_id.
    LOOP AT lt_act INTO ls_act.
      READ TABLE lt_src ASSIGNING <ls_cnt>
        WITH TABLE KEY key = CONV string( ls_act-source ).
      IF sy-subrc = 0.
        <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
      ELSE.
        ls_cnt-key = ls_act-source. ls_cnt-cnt = 1.
        INSERT ls_cnt INTO TABLE lt_src.
      ENDIF.
      IF ls_act-tcode IS NOT INITIAL.
        READ TABLE lt_tc ASSIGNING <ls_cnt>
          WITH TABLE KEY key = CONV string( ls_act-tcode ).
        IF sy-subrc = 0.
          <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
        ELSE.
          ls_cnt-key = ls_act-tcode. ls_cnt-cnt = 1.
          INSERT ls_cnt INTO TABLE lt_tc.
        ENDIF.
      ENDIF.
    ENDLOOP.

    lcl_mail=>add_line( EXPORTING iv_text = space
                        CHANGING  ct_body = ct_body ).
    lcl_mail=>add_line(
      EXPORTING
        iv_text = 'ÖZET – kaynak bazında hareket sayısı'
      CHANGING
        ct_body = ct_body ).
    LOOP AT lt_src INTO ls_cnt.
      lcl_mail=>add_line(
        EXPORTING
          iv_text = |  { ls_cnt-key WIDTH = 15 } : { ls_cnt-cnt }|
        CHANGING
          ct_body = ct_body ).
    ENDLOOP.

    IF lt_tc IS NOT INITIAL.
      lcl_mail=>add_line( EXPORTING iv_text = space
                          CHANGING  ct_body = ct_body ).
      lcl_mail=>add_line( EXPORTING iv_text = 'Kullanılan işlem kodları'
                          CHANGING  ct_body = ct_body ).
      LOOP AT lt_tc INTO ls_cnt.
        lv_n = lv_n + 1.
        IF lv_n > 40.
          lcl_mail=>add_line(
            EXPORTING
              iv_text = '  ... (tam liste ZBY_RAPOR)'
            CHANGING
              ct_body = ct_body ).
          EXIT.
        ENDIF.
        lcl_mail=>add_line(
          EXPORTING
            iv_text = |  { ls_cnt-key WIDTH = 20 } : { ls_cnt-cnt }|
          CHANGING
            ct_body = ct_body ).
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

*======================================================================*
* 5) ARKA PLAN JOB
*======================================================================*
  METHOD run_job.
    DATA: lt_req TYPE ty_t_talep,
          ls_req TYPE zby_talep,
          lv_now TYPE timestamp,
          lv_ok  TYPE abap_bool,
          lv_cnt TYPE i.

    lv_now = lcl_db=>now_ts( ).

    WRITE: / 'ZBY – süreli yetki job', sy-datum DD/MM/YYYY, sy-uzeit.
    IF iv_test = abap_true.
      WRITE: / '*** TEST MODU – değişiklik yapılmaz ***'.
    ENDIF.
    ULINE.

    SELECT * FROM zby_talep INTO TABLE lt_req
      WHERE status = gc_st-planned OR status = gc_st-active.

    LOOP AT lt_req INTO ls_req.
      CASE ls_req-status.

        WHEN gc_st-planned.
*         a) Başlangıç zamanı gelen yetkiler aktif edilir
          CHECK lcl_db=>to_ts( iv_date = ls_req-valid_from_date
                               iv_time = ls_req-valid_from_time )
                <= lv_now.
          lv_cnt = lv_cnt + 1.
          WRITE: / ls_req-req_id, ls_req-bname, ls_req-agr_name,
                 'AKTİF EDİLİYOR'.
          CHECK iv_test = abap_false.
          IF lcl_db=>to_ts( iv_date = ls_req-valid_to_date
                            iv_time = ls_req-valid_to_time ) <= lv_now.
*           Bitiş de geçmişse hiç atanmadan kapatılır
            ls_req-status   = gc_st-expired.
            ls_req-last_msg = 'Başlangıç zamanında atanamadı, '
                            & 'süre doldu'.
            UPDATE zby_talep FROM ls_req.
            lcl_db=>log( iv_id = ls_req-req_id iv_action = 'BITIS'
                         iv_msg = ls_req-last_msg ).
            COMMIT WORK.
            CONTINUE.
          ENDIF.
          activate( IMPORTING ev_ok = lv_ok CHANGING cs_req = ls_req ).
          WRITE: / '   ->', ls_req-last_msg.

        WHEN gc_st-active.
          IF lcl_db=>to_ts( iv_date = ls_req-valid_to_date
                            iv_time = ls_req-valid_to_time ) <= lv_now.
*           b) Süresi dolan yetkiler geri alınır, rapor hazırlanır
            lv_cnt = lv_cnt + 1.
            WRITE: / ls_req-req_id, ls_req-bname, ls_req-agr_name,
                   'SÜRE DOLDU'.
            CHECK iv_test = abap_false.
            end_access( EXPORTING iv_status = gc_st-expired
                        IMPORTING ev_ok = lv_ok
                        CHANGING cs_req = ls_req ).
            IF lv_ok = abap_true.
              WRITE: / '   ->', 'Yetki geri alındı,', ls_req-act_count,
                     'hareket'.
            ELSE.
              WRITE: / '   ->', 'HATA:', ls_req-last_msg
                     COLOR COL_NEGATIVE.
            ENDIF.
          ELSE.
*           c) Aktif yetkiler: hareketler artımlı toplanır (STAD kısa
*              süre saklandığı için veri kaybını önler)
            CHECK iv_test = abap_false.
            collect_and_store( EXPORTING iv_upto = lv_now
                               CHANGING cs_req = ls_req ).
            COMMIT WORK.
            WRITE: / ls_req-req_id, ls_req-bname,
                   'aktif – toplanan hareket:', ls_req-act_count.
          ENDIF.
      ENDCASE.
    ENDLOOP.

    ULINE.
    WRITE: / 'Durum değişen talep sayısı:', lv_cnt.
  ENDMETHOD.

*======================================================================*
* UI yardımcıları
*======================================================================*
  METHOD ask_note.
    CLEAR: ev_cancel, ev_note, p_note.
    gv_t92 = iv_title.
    DO.
      CALL SELECTION-SCREEN 9200 STARTING AT 10 8.
      IF sy-subrc <> 0.
        ev_cancel = abap_true.
        RETURN.
      ENDIF.
      IF iv_mandatory = abap_false OR p_note IS NOT INITIAL.
        EXIT.
      ENDIF.
      MESSAGE 'Gerekçe zorunludur' TYPE 'S' DISPLAY LIKE 'E'.
    ENDDO.
    ev_note = p_note.
  ENDMETHOD.

  METHOD confirm.
    DATA: lv_answer TYPE c LENGTH 1,
          lv_text   TYPE c LENGTH 400.

    lv_text = iv_question.
    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar              = 'Süreli yetki'
        text_question         = lv_text
        text_button_1         = 'Evet'
        text_button_2         = 'Hayır'
        default_button        = '2'
        display_cancel_button = space
      IMPORTING
        answer                = lv_answer
      EXCEPTIONS
        text_not_found        = 1
        OTHERS                = 2.
    rv = xsdbool( sy-subrc = 0 AND lv_answer = '1' ).
  ENDMETHOD.

  METHOD rcpt_requester.
    APPEND lcl_mail=>user_rcpt( is_req-bname ) TO rt.
  ENDMETHOD.

  METHOD notify.
    DATA lt_body TYPE soli_tab.

    CHECK lcl_cfg=>flag( 'EPOSTA' ) = abap_true.
    lt_body = lcl_mail=>req_body( is_req = is_req iv_intro = iv_intro
                                  iv_action = iv_action ).
    IF iv_summary = abap_true.
      summary_lines( EXPORTING iv_req_id = is_req-req_id
                     CHANGING ct_body = lt_body ).
    ENDIF.
    lcl_mail=>send( it_rcpt = it_rcpt iv_subject = iv_subject
                    it_body = lt_body ).
  ENDMETHOD.

  METHOD set_column.
    DATA: lo_col TYPE REF TO cl_salv_column_table,
          lv_s   TYPE scrtext_s,
          lv_m   TYPE scrtext_m,
          lv_l   TYPE scrtext_l.

    TRY.
        lo_col ?= io_cols->get_column( iv_name ).
      CATCH cx_salv_not_found.
        RETURN.
    ENDTRY.
    IF iv_text IS NOT INITIAL.
      lv_s = iv_text.
      lv_m = iv_text.
      lv_l = iv_text.
      lo_col->set_short_text( lv_s ).
      lo_col->set_medium_text( lv_m ).
      lo_col->set_long_text( lv_l ).
    ENDIF.
    IF iv_hotspot = abap_true.
      lo_col->set_icon( abap_true ).
      lo_col->set_cell_type( if_salv_c_cell_type=>hotspot ).
    ENDIF.
    IF iv_hide = abap_true.
      lo_col->set_visible( abap_false ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Mod belirleme
*----------------------------------------------------------------------*
CLASS lcl_mode DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS current RETURNING VALUE(rv) TYPE char1.
ENDCLASS.

CLASS lcl_mode IMPLEMENTATION.
  METHOD current.
    IF gv_fixed_mode IS NOT INITIAL.
      rv = gv_fixed_mode.
    ELSE.
      CASE abap_true.
        WHEN rb_tlp.  rv = gc_mode-request.
        WHEN rb_onay. rv = gc_mode-approve.
        WHEN rb_bas.  rv = gc_mode-basis.
        WHEN rb_rap.  rv = gc_mode-report.
        WHEN rb_job.  rv = gc_mode-job.
      ENDCASE.
    ENDIF.
    IF rv = gc_mode-request AND rb_my = abap_true.
      rv = gc_mode-my.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Olaylar
*----------------------------------------------------------------------*
DATA go_app TYPE REF TO lcl_app.

INITIALIZATION.
  gv_tm  = 'İşlem'.
  gv_tq  = 'Yetki talebi'.
  gv_tt  = 'Yeni talep'.
  gv_tl  = 'Seçim'.
  gv_tj  = 'Arka plan job'.
  gv_t91 = 'Yetki tanımla (tarih / saat aralığı)'.
  gv_t92 = 'Not'.

* İşlem koduna göre sabit mod
  CASE sy-tcode.
    WHEN 'ZBY_TALEP'. gv_fixed_mode = gc_mode-request.
    WHEN 'ZBY_ONAY'.  gv_fixed_mode = gc_mode-approve.
    WHEN 'ZBY_BASIS'. gv_fixed_mode = gc_mode-basis.
    WHEN 'ZBY_RAPOR'. gv_fixed_mode = gc_mode-report.
  ENDCASE.

  p_role = lcl_cfg=>role( ).
  p_frd  = sy-datum.
  p_frt  = sy-uzeit.
  lcl_db=>split_ts(
    EXPORTING iv_ts   = lcl_db=>add_secs(
                          iv_ts   = lcl_db=>to_ts( iv_date = sy-datum
                                                   iv_time = sy-uzeit )
                          iv_secs = 4 * 3600 )
    IMPORTING ev_date = p_tod
              ev_time = p_tot ).

AT SELECTION-SCREEN OUTPUT.
  CHECK sy-dynnr = '1000'.
  gv_mode = lcl_mode=>current( ).
  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'MOD'.
        screen-active = COND #( WHEN gv_fixed_mode IS INITIAL THEN 1
                                ELSE 0 ).
      WHEN 'RQM'.
        screen-active = COND #( WHEN gv_mode = gc_mode-request OR
                                gv_mode = gc_mode-my THEN 1 ELSE 0 ).
      WHEN 'TLP'.
        screen-active = COND #( WHEN gv_mode = gc_mode-request THEN 1
                                ELSE 0 ).
      WHEN 'TRO'.
        screen-active = COND #( WHEN gv_mode = gc_mode-request THEN 1
                                ELSE 0 ).
        " rol sabit (ZBY_PARAM-ROL)
        screen-input  = 0.
      WHEN 'LST'.
        screen-active = COND #( WHEN gv_mode = gc_mode-my
                                  OR gv_mode = gc_mode-approve
                                  OR gv_mode = gc_mode-basis
                                  OR gv_mode = gc_mode-report
                                THEN 1 ELSE 0 ).
      WHEN 'JOB'.
        screen-active = COND #( WHEN gv_mode = gc_mode-job THEN 1
                                ELSE 0 ).
    ENDCASE.
    MODIFY SCREEN.
  ENDLOOP.

AT SELECTION-SCREEN.
  CHECK sy-dynnr = '1000'.
  gv_mode = lcl_mode=>current( ).
  IF sy-ucomm = 'ONLI' AND gv_mode = gc_mode-request.
    IF p_frd IS INITIAL OR p_tod IS INITIAL.
      MESSAGE 'Başlangıç ve bitiş tarihi zorunludur' TYPE 'E'.
    ENDIF.
  ENDIF.

START-OF-SELECTION.
  gv_mode = lcl_mode=>current( ).
  IF sy-batch = abap_true.
    " job her zaman job modunda
    gv_mode = gc_mode-job.
  ENDIF.

  CREATE OBJECT go_app.
  CASE gv_mode.
    WHEN gc_mode-request.
      go_app->create_request( ).
    WHEN gc_mode-job.
      go_app->run_job( p_test ).
    WHEN OTHERS.
      go_app->show_list( gv_mode ).
  ENDCASE.
