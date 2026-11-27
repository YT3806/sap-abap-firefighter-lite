*&---------------------------------------------------------------------*
*& Report ZBY_DDIC_KURULUM
*&---------------------------------------------------------------------*
*& ZBY süreli yetki çözümünün DDIC nesnelerini oluşturur ve aktive
*& eder:
*&   Domain   : ZBY_STATUS, ZBY_USER_TYPE
*&   Veri el. : ZBY_REQ_ID, ZBY_STATUS, ZBY_USER_TYPE
*&   Tablolar : ZBY_TALEP, ZBY_HAREKET, ZBY_KULLANICI, ZBY_PARAM,
*&              ZBY_LOG
*& ve ZBY_PARAM tablosuna varsayılan parametreleri yazar.
*&
*& Paket: P_DEVC (varsayılan $TMP). Bir kez çalıştırılır; tekrar
*& çalıştırmak tanımları günceller (veri silinmez).
*& Yetki: S_DEVELOP (DDIC oluşturma/aktivasyon)
*&---------------------------------------------------------------------*
REPORT zby_ddic_kurulum.

PARAMETERS: p_devc  TYPE devclass DEFAULT '$TMP',
            p_param AS CHECKBOX DEFAULT 'X',
            p_test  AS CHECKBOX DEFAULT 'X'.

TYPES: ty_t_dd03p TYPE STANDARD TABLE OF dd03p WITH DEFAULT KEY,
       ty_t_dd07v TYPE STANDARD TABLE OF dd07v WITH DEFAULT KEY.

DATA: gt_fields TYPE ty_t_dd03p,
      gv_errors TYPE i.

*----------------------------------------------------------------------*
CLASS lcl_ddic DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS tadir
      IMPORTING iv_object TYPE trobjtype
                iv_name   TYPE csequence.
    CLASS-METHODS domain
      IMPORTING iv_name   TYPE domname
                iv_text   TYPE csequence
                iv_type   TYPE datatype_d
                iv_leng   TYPE i
                it_values TYPE ty_t_dd07v OPTIONAL.
    CLASS-METHODS dtel
      IMPORTING iv_name   TYPE rollname
                iv_text   TYPE csequence
                iv_short  TYPE csequence
                iv_medium TYPE csequence
                iv_long   TYPE csequence
                iv_domain TYPE domname OPTIONAL
                iv_type   TYPE datatype_d OPTIONAL
                iv_leng   TYPE i OPTIONAL.
    CLASS-METHODS add_field
      IMPORTING iv_field TYPE fieldname
                iv_key   TYPE abap_bool DEFAULT abap_false
                iv_dtel  TYPE rollname OPTIONAL
                iv_type  TYPE datatype_d OPTIONAL
                iv_leng  TYPE i OPTIONAL
                iv_text  TYPE csequence OPTIONAL.
    CLASS-METHODS table
      IMPORTING iv_name    TYPE tabname
                iv_text    TYPE csequence
                iv_contflg TYPE contflag DEFAULT 'A'
                iv_tabart  TYPE tabart DEFAULT 'APPL1'.
    CLASS-METHODS result
      IMPORTING iv_object TYPE csequence
                iv_rc     TYPE sysubrc
                iv_step   TYPE csequence.
ENDCLASS.

CLASS lcl_ddic IMPLEMENTATION.

  METHOD result.
    IF iv_rc = 0.
      WRITE: / iv_object, iv_step, 'OK' COLOR COL_POSITIVE.
    ELSEIF iv_rc = 4.
      WRITE: / iv_object, iv_step, 'uyarı (rc=4)' COLOR COL_TOTAL.
    ELSE.
      WRITE: / iv_object, iv_step, 'HATA rc=', iv_rc
               COLOR COL_NEGATIVE.
      gv_errors = gv_errors + 1.
    ENDIF.
  ENDMETHOD.

  METHOD tadir.
    DATA lv_name TYPE sobj_name.

    lv_name = iv_name.
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus     = space
        wi_tadir_pgmid    = 'R3TR'
        wi_tadir_object   = iv_object
        wi_tadir_obj_name = lv_name
        wi_tadir_author   = sy-uname
        wi_tadir_devclass = p_devc
      EXCEPTIONS
        OTHERS            = 1.
*   Kayıt zaten varsa hata verebilir; bu durumda devam edilir
  ENDMETHOD.

  METHOD domain.
    DATA: ls_dd01v TYPE dd01v,
          lt_dd07v TYPE ty_t_dd07v,
          ls_dd07v TYPE dd07v,
          lv_rc    TYPE sysubrc.

    tadir( iv_object = 'DOMA' iv_name = iv_name ).

    ls_dd01v-domname    = iv_name.
    ls_dd01v-ddlanguage = sy-langu.
    ls_dd01v-datatype   = iv_type.
    ls_dd01v-leng       = iv_leng.
    ls_dd01v-outputlen  = iv_leng.
    ls_dd01v-ddtext     = iv_text.
    IF it_values IS NOT INITIAL.
      ls_dd01v-valexi = abap_true.
    ENDIF.
    LOOP AT it_values INTO ls_dd07v.
      ls_dd07v-domname    = iv_name.
      ls_dd07v-ddlanguage = sy-langu.
      APPEND ls_dd07v TO lt_dd07v.
    ENDLOOP.

    CALL FUNCTION 'DDIF_DOMA_PUT'
      EXPORTING
        name              = iv_name
        dd01v_wa          = ls_dd01v
      TABLES
        dd07v_tab         = lt_dd07v
      EXCEPTIONS
        doma_not_found    = 1
        name_inconsistent = 2
        doma_inconsistent = 3
        put_failure       = 4
        put_refused       = 5
        OTHERS            = 6.
    result( iv_object = iv_name
            iv_rc     = sy-subrc
            iv_step   = 'DOMA kaydet' ).
    CHECK sy-subrc = 0.

    CALL FUNCTION 'DDIF_DOMA_ACTIVATE'
      EXPORTING
        name        = iv_name
      IMPORTING
        rc          = lv_rc
      EXCEPTIONS
        not_found   = 1
        put_failure = 2
        OTHERS      = 3.
    IF sy-subrc <> 0.
      lv_rc = 8.
    ENDIF.
    result( iv_object = iv_name
            iv_rc     = lv_rc
            iv_step   = 'DOMA aktive' ).
  ENDMETHOD.

  METHOD dtel.
    DATA: ls_dd04v TYPE dd04v,
          lv_rc    TYPE sysubrc.

    tadir( iv_object = 'DTEL' iv_name = iv_name ).

    ls_dd04v-rollname   = iv_name.
    ls_dd04v-ddlanguage = sy-langu.
    ls_dd04v-ddtext     = iv_text.
    ls_dd04v-reptext    = iv_medium.
    ls_dd04v-scrtext_s  = iv_short.
    ls_dd04v-scrtext_m  = iv_medium.
    ls_dd04v-scrtext_l  = iv_long.
    ls_dd04v-headlen    = 20.
    ls_dd04v-scrlen1    = 10.
    ls_dd04v-scrlen2    = 20.
    ls_dd04v-scrlen3    = 40.
    IF iv_domain IS NOT INITIAL.
      ls_dd04v-domname  = iv_domain.
    ELSE.
      ls_dd04v-datatype  = iv_type.
      ls_dd04v-leng      = iv_leng.
      ls_dd04v-outputlen = iv_leng.
    ENDIF.

    CALL FUNCTION 'DDIF_DTEL_PUT'
      EXPORTING
        name              = iv_name
        dd04v_wa          = ls_dd04v
      EXCEPTIONS
        dtel_not_found    = 1
        name_inconsistent = 2
        dtel_inconsistent = 3
        put_failure       = 4
        put_refused       = 5
        OTHERS            = 6.
    result( iv_object = iv_name
            iv_rc     = sy-subrc
            iv_step   = 'DTEL kaydet' ).
    CHECK sy-subrc = 0.

    CALL FUNCTION 'DDIF_DTEL_ACTIVATE'
      EXPORTING
        name        = iv_name
      IMPORTING
        rc          = lv_rc
      EXCEPTIONS
        not_found   = 1
        put_failure = 2
        OTHERS      = 3.
    IF sy-subrc <> 0.
      lv_rc = 8.
    ENDIF.
    result( iv_object = iv_name
            iv_rc     = lv_rc
            iv_step   = 'DTEL aktive' ).
  ENDMETHOD.

  METHOD add_field.
    DATA ls_fld TYPE dd03p.

    ls_fld-fieldname  = iv_field.
    ls_fld-position   = lines( gt_fields ) + 1.
    ls_fld-keyflag    = iv_key.
    ls_fld-notnull    = iv_key.
    ls_fld-ddlanguage = sy-langu.
    IF iv_dtel IS NOT INITIAL.
      ls_fld-rollname = iv_dtel.
    ELSE.
*     Önceden tanımlı (built-in) tip
      ls_fld-datatype = iv_type.
      ls_fld-leng     = iv_leng.
      ls_fld-ddtext   = iv_text.
    ENDIF.
    APPEND ls_fld TO gt_fields.
  ENDMETHOD.

  METHOD table.
    DATA: ls_dd02v TYPE dd02v,
          ls_dd09l TYPE dd09l,
          ls_fld   TYPE dd03p,
          lt_fld   TYPE ty_t_dd03p,
          lv_rc    TYPE sysubrc.

    tadir( iv_object = 'TABL' iv_name = iv_name ).

    ls_dd02v-tabname    = iv_name.
    ls_dd02v-ddlanguage = sy-langu.
    ls_dd02v-tabclass   = 'TRANSP'.
    ls_dd02v-clidep     = abap_true.
    ls_dd02v-ddtext     = iv_text.
    ls_dd02v-contflag   = iv_contflg.
    ls_dd02v-mainflag   = 'X'.      " SE16/SM30 bakımı serbest
    ls_dd02v-exclass    = '1'.      " genişletilemez

    ls_dd09l-tabname    = iv_name.
    ls_dd09l-as4local   = 'A'.
    ls_dd09l-tabkat     = '0'.
    ls_dd09l-tabart     = iv_tabart.
    ls_dd09l-bufallow   = 'N'.

    LOOP AT gt_fields INTO ls_fld.
      ls_fld-tabname = iv_name.
      APPEND ls_fld TO lt_fld.
    ENDLOOP.

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name              = iv_name
        dd02v_wa          = ls_dd02v
        dd09l_wa          = ls_dd09l
      TABLES
        dd03p_tab         = lt_fld
      EXCEPTIONS
        tabl_not_found    = 1
        name_inconsistent = 2
        tabl_inconsistent = 3
        put_failure       = 4
        put_refused       = 5
        OTHERS            = 6.
    result( iv_object = iv_name
            iv_rc     = sy-subrc
            iv_step   = 'TABL kaydet' ).
    CLEAR gt_fields.
    CHECK sy-subrc = 0.

    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name        = iv_name
      IMPORTING
        rc          = lv_rc
      EXCEPTIONS
        not_found   = 1
        put_failure = 2
        OTHERS      = 3.
    IF sy-subrc <> 0.
      lv_rc = 8.
    ENDIF.
    result( iv_object = iv_name
            iv_rc     = lv_rc
            iv_step   = 'TABL aktive (DB tablosu)' ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
FORM build.
  DATA lt_val TYPE ty_t_dd07v.

*--- Domain'ler
  lt_val = VALUE #(
    ( valpos = 1 domvalue_l = 'N' ddtext = 'Onay bekliyor' )
    ( valpos = 2 domvalue_l = 'O'
      ddtext = 'Onaylandı - Basis bekliyor' )
    ( valpos = 3 domvalue_l = 'P' ddtext = 'Planlandı' )
    ( valpos = 4 domvalue_l = 'A' ddtext = 'Yetki aktif' )
    ( valpos = 5 domvalue_l = 'T' ddtext = 'Kullanıcı tamamladı' )
    ( valpos = 6 domvalue_l = 'E' ddtext = 'Süre doldu' )
    ( valpos = 7 domvalue_l = 'S' ddtext = 'Basis sonlandırdı' )
    ( valpos = 8 domvalue_l = 'R' ddtext = 'Reddedildi' )
    ( valpos = 9 domvalue_l = 'C' ddtext = 'İptal edildi' ) ).
  lcl_ddic=>domain( iv_name   = 'ZBY_STATUS'
                    iv_text   = 'Süreli yetki talep durumu'
                    iv_type   = 'CHAR'
                    iv_leng   = 1
                    it_values = lt_val ).

  lt_val = VALUE #(
    ( valpos = 1 domvalue_l = 'O' ddtext = 'Onaycı' )
    ( valpos = 2 domvalue_l = 'B' ddtext = 'Basis' )
    ( valpos = 3 domvalue_l = 'D' ddtext = 'Denetçi' ) ).
  lcl_ddic=>domain( iv_name   = 'ZBY_USER_TYPE'
                    iv_text   = 'Süreli yetki kullanıcı tipi'
                    iv_type   = 'CHAR'
                    iv_leng   = 1
                    it_values = lt_val ).

*--- Veri elemanları
  lcl_ddic=>dtel( iv_name   = 'ZBY_REQ_ID'
                  iv_text   = 'Süreli yetki talep numarası'
                  iv_short  = 'Talep No'
                  iv_medium = 'Talep No'
                  iv_long   = 'Talep numarası'
                  iv_type   = 'NUMC'
                  iv_leng   = 10 ).
  lcl_ddic=>dtel( iv_name   = 'ZBY_STATUS'
                  iv_text   = 'Süreli yetki talep durumu'
                  iv_short  = 'Durum'
                  iv_medium = 'Durum'
                  iv_long   = 'Talep durumu'
                  iv_domain = 'ZBY_STATUS' ).
  lcl_ddic=>dtel( iv_name   = 'ZBY_USER_TYPE'
                  iv_text   = 'Süreli yetki kullanıcı tipi'
                  iv_short  = 'Tip'
                  iv_medium = 'Kullanıcı tipi'
                  iv_long   = 'Kullanıcı tipi (O/B/D)'
                  iv_domain = 'ZBY_USER_TYPE' ).

*--- ZBY_TALEP
  lcl_ddic=>add_field( iv_field = 'MANDT'
                       iv_key   = abap_true
                       iv_dtel  = 'MANDT' ).
  lcl_ddic=>add_field( iv_field = 'REQ_ID'
                       iv_key   = abap_true
                       iv_dtel  = 'ZBY_REQ_ID' ).
  lcl_ddic=>add_field( iv_field = 'BNAME'
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'AGR_NAME'
                       iv_dtel  = 'AGR_NAME' ).
  lcl_ddic=>add_field( iv_field = 'REQ_FROM_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'REQ_FROM_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'REQ_TO_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'REQ_TO_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'TICKET'
                       iv_dtel  = 'TEXT40' ).
  lcl_ddic=>add_field( iv_field = 'REASON'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'STATUS'
                       iv_dtel  = 'ZBY_STATUS' ).
  lcl_ddic=>add_field( iv_field = 'CR_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'CR_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'APPROVER'
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'APPR_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'APPR_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'APPR_NOTE'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'BASIS_USER'
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'BASIS_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'BASIS_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'BASIS_NOTE'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'VALID_FROM_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'VALID_FROM_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'VALID_TO_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'VALID_TO_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'ROLE_PREEXIST'
                       iv_dtel  = 'FLAG' ).
  lcl_ddic=>add_field( iv_field = 'ROLE_ASSIGNED'
                       iv_dtel  = 'FLAG' ).
  lcl_ddic=>add_field( iv_field = 'ENDED_BY'
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'ENDED_DATE'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'ENDED_TIME'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'COLLECTED_TS'
                       iv_dtel  = 'TIMESTAMP' ).
  lcl_ddic=>add_field( iv_field = 'ACT_COUNT'
                       iv_dtel  = 'INT4' ).
  lcl_ddic=>add_field( iv_field = 'LAST_MSG'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>table( iv_name = 'ZBY_TALEP'
                   iv_text = 'Süreli yetki talepleri' ).

*--- ZBY_HAREKET
  lcl_ddic=>add_field( iv_field = 'MANDT'
                       iv_key   = abap_true
                       iv_dtel  = 'MANDT' ).
  lcl_ddic=>add_field( iv_field = 'REQ_ID'
                       iv_key   = abap_true
                       iv_dtel  = 'ZBY_REQ_ID' ).
  lcl_ddic=>add_field( iv_field = 'SEQ'
                       iv_key   = abap_true
                       iv_dtel  = 'INT4' ).
  lcl_ddic=>add_field( iv_field = 'DATUM'
                       iv_dtel  = 'SYDATUM' ).
  lcl_ddic=>add_field( iv_field = 'UZEIT'
                       iv_dtel  = 'SYUZEIT' ).
  lcl_ddic=>add_field( iv_field = 'SOURCE'
                       iv_type  = 'CHAR'
                       iv_leng  = 15
                       iv_text  = 'Kaynak' ).
  lcl_ddic=>add_field( iv_field = 'TCODE'
                       iv_dtel  = 'TCODE' ).
  lcl_ddic=>add_field( iv_field = 'PROG_NAME'
                       iv_dtel  = 'PROGNAME' ).
  lcl_ddic=>add_field( iv_field = 'OBJECT'
                       iv_type  = 'CHAR'
                       iv_leng  = 120
                       iv_text  = 'Nesne / tablo / anahtar' ).
  lcl_ddic=>add_field( iv_field = 'ACTION'
                       iv_dtel  = 'TEXT60' ).
  lcl_ddic=>add_field( iv_field = 'OLD_VALUE'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'NEW_VALUE'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'TEXT'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'TERMINAL'
                       iv_type  = 'CHAR'
                       iv_leng  = 20
                       iv_text  = 'Terminal' ).
  lcl_ddic=>table( iv_name = 'ZBY_HAREKET'
                   iv_text = 'Süreli yetki - kullanıcı hareketleri' ).

*--- ZBY_KULLANICI (customizing)
  lcl_ddic=>add_field( iv_field = 'MANDT'
                       iv_key   = abap_true
                       iv_dtel  = 'MANDT' ).
  lcl_ddic=>add_field( iv_field = 'BNAME'
                       iv_key   = abap_true
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'USER_TYPE'
                       iv_key   = abap_true
                       iv_dtel  = 'ZBY_USER_TYPE' ).
  lcl_ddic=>add_field( iv_field = 'EMAIL'
                       iv_dtel  = 'AD_SMTPADR' ).
  lcl_ddic=>add_field( iv_field = 'ACTIVE'
                       iv_dtel  = 'FLAG' ).
  lcl_ddic=>table( iv_name    = 'ZBY_KULLANICI'
                   iv_text    = 'Süreli yetki - onaycı/basis/denetçi'
                   iv_contflg = 'C'
                   iv_tabart  = 'APPL2' ).

*--- ZBY_PARAM (customizing)
  lcl_ddic=>add_field( iv_field = 'MANDT'
                       iv_key   = abap_true
                       iv_dtel  = 'MANDT' ).
  lcl_ddic=>add_field( iv_field = 'PARAM'
                       iv_key   = abap_true
                       iv_type  = 'CHAR'
                       iv_leng  = 30
                       iv_text  = 'Parametre' ).
  lcl_ddic=>add_field( iv_field = 'VALUE'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>add_field( iv_field = 'DESCRIPTION'
                       iv_dtel  = 'TEXT60' ).
  lcl_ddic=>table( iv_name    = 'ZBY_PARAM'
                   iv_text    = 'Süreli yetki - parametreler'
                   iv_contflg = 'C'
                   iv_tabart  = 'APPL2' ).

*--- ZBY_LOG
  lcl_ddic=>add_field( iv_field = 'MANDT'
                       iv_key   = abap_true
                       iv_dtel  = 'MANDT' ).
  lcl_ddic=>add_field( iv_field = 'REQ_ID'
                       iv_key   = abap_true
                       iv_dtel  = 'ZBY_REQ_ID' ).
  lcl_ddic=>add_field( iv_field = 'LOG_TS'
                       iv_key   = abap_true
                       iv_dtel  = 'TIMESTAMPL' ).
  lcl_ddic=>add_field( iv_field = 'UNAME'
                       iv_dtel  = 'XUBNAME' ).
  lcl_ddic=>add_field( iv_field = 'ACTION'
                       iv_type  = 'CHAR'
                       iv_leng  = 20
                       iv_text  = 'İşlem' ).
  lcl_ddic=>add_field( iv_field = 'MSG'
                       iv_dtel  = 'TEXT255' ).
  lcl_ddic=>table( iv_name = 'ZBY_LOG'
                   iv_text = 'Süreli yetki - denetim izi' ).
ENDFORM.

*----------------------------------------------------------------------*
* Varsayılan parametreler (dinamik: tablo derleme anında yok)
*----------------------------------------------------------------------*
FORM default_params.
  TYPES: BEGIN OF ty_p,
           param TYPE c LENGTH 30,
           value TYPE c LENGTH 255,
           descr TYPE c LENGTH 60,
         END OF ty_p.
  DATA: lt_p  TYPE STANDARD TABLE OF ty_p WITH DEFAULT KEY,
        ls_p  TYPE ty_p,
        lr_wa TYPE REF TO data,
        lv_n  TYPE i.
  FIELD-SYMBOLS: <ls_wa> TYPE any,
                 <lv_f>  TYPE any.

  lt_p = VALUE #(
    ( param = 'ROL'       value = 'Z_SURELI_YETKI'
      descr = 'Atanacak rol' )
    ( param = 'MAKS_SAAT' value = '24'
      descr = 'En uzun yetki süresi (saat, üst sınır 24)' )
    ( param = 'EPOSTA'    value = 'X'
      descr = 'E-posta gönder (X/boş)' )
    ( param = 'KAYNAK_STAD' value = 'X'
      descr = 'Rapor: işlem kodları/programlar' )
    ( param = 'KAYNAK_CD' value = 'X'
      descr = 'Rapor: değişiklik belgeleri' )
    ( param = 'KAYNAK_TABLOG' value = 'X'
      descr = 'Rapor: tablo logu' )
    ( param = 'KAYNAK_JOB' value = 'X'
      descr = 'Rapor: arka plan job' )
    ( param = 'KAYNAK_TRANSPORT' value = 'X'
      descr = 'Rapor: transport talepleri' )
    ( param = 'KAYNAK_SE16N' value = 'X'
      descr = 'Rapor: SE16N değişiklikleri' )
    ( param = 'KAYNAK_AUDIT' value = 'X'
      descr = 'Rapor: Security Audit Log (SM20)' )
    ( param = 'MAIL_GONDEREN' value = ''
      descr = 'E-posta gönderen adresi (boş: SAP varsayılanı)' ) ).

  TRY.
      CREATE DATA lr_wa TYPE ('ZBY_PARAM').
    CATCH cx_sy_create_data_error.
      WRITE: / 'ZBY_PARAM aktif değil, parametreler yazılamadı'
               COLOR COL_NEGATIVE.
      RETURN.
  ENDTRY.
  ASSIGN lr_wa->* TO <ls_wa>.

  LOOP AT lt_p INTO ls_p.
    CLEAR <ls_wa>.
    ASSIGN COMPONENT 'PARAM' OF STRUCTURE <ls_wa> TO <lv_f>.
    <lv_f> = ls_p-param.
    ASSIGN COMPONENT 'VALUE' OF STRUCTURE <ls_wa> TO <lv_f>.
    <lv_f> = ls_p-value.
    ASSIGN COMPONENT 'DESCRIPTION' OF STRUCTURE <ls_wa> TO <lv_f>.
    <lv_f> = ls_p-descr.
*   Mevcut kayıt korunur (INSERT, MODIFY değil)
    INSERT ('ZBY_PARAM') FROM <ls_wa>.
    IF sy-subrc = 0.
      lv_n = lv_n + 1.
    ENDIF.
  ENDLOOP.
  COMMIT WORK.
  WRITE: / 'ZBY_PARAM: eklenen varsayılan parametre sayısı:', lv_n.
ENDFORM.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  AUTHORITY-CHECK OBJECT 'S_DEVELOP'
    ID 'DEVCLASS' FIELD p_devc
    ID 'OBJTYPE'  FIELD 'TABL'
    ID 'OBJNAME'  DUMMY
    ID 'P_GROUP'  DUMMY
    ID 'ACTVT'    FIELD '02'.
  IF sy-subrc <> 0.
    WRITE: / 'S_DEVELOP yetkisi yok (TABL / 02 / paket', p_devc, ')'
             COLOR COL_NEGATIVE.
    RETURN.
  ENDIF.

  IF p_test = abap_true.
    WRITE: / 'TEST MODU: hiçbir nesne oluşturulmadı.'.
    WRITE: / 'Oluşturulacaklar (paket', p_devc, '):'.
    WRITE: / '  DOMA ZBY_STATUS, ZBY_USER_TYPE'.
    WRITE: / '  DTEL ZBY_REQ_ID, ZBY_STATUS, ZBY_USER_TYPE'.
    WRITE: / '  TABL ZBY_TALEP, ZBY_HAREKET, ZBY_KULLANICI,',
           / '       ZBY_PARAM, ZBY_LOG'.
    WRITE: / 'Gerçek çalıştırma için "Test modu" işaretini kaldırın.'.
    RETURN.
  ENDIF.

  PERFORM build.
  ULINE.
  IF gv_errors = 0.
    WRITE: / 'Tüm DDIC nesneleri oluşturuldu ve aktive edildi.'
             COLOR COL_POSITIVE.
    IF p_param = abap_true.
      PERFORM default_params.
    ENDIF.
  ELSE.
    WRITE: / gv_errors,
             'adımda hata oluştu. SE11 aktivasyon logunu kontrol edin.'
             COLOR COL_NEGATIVE.
  ENDIF.
