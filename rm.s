* rm - remove file
*
* Itagaki Fumihiko  8-Aug-92  Create.
*
* Usage: rm [ -firvR ] <ファイル> ...

.include doscall.h
.include error.h
.include limits.h
.include stat.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strcpy
.xref strfor1
.xref cat_pathname
.xref strip_excessive_slashes

MAXRECURSE	equ	32	*  サブディレクトリを削除するために再帰する回数の上限．
				*  MAXDIR （パス名のディレクトリ部 "/1/2/3/../" の長さ）
				*  が 64 であるから、31で充分であるが，1つぶん余裕を持って
				*  32 としておく．
				*  スタック量にかかわる．

GETSLEN		equ	32	*  端末に問い合わせる際の入力バイト数の上限．
				*  実用上，1バイトあれば充分であるし，2バイト文字が入力される
				*  ことを考慮しても 2バイトあれば充分であるが，体裁が悪いので
				*  32バイト程度は入力できるようにしておく．
				*  行入力バッファ量にかかわる．

FLAG_f		equ	0
FLAG_i		equ	1
FLAG_r		equ	2
FLAG_v		equ	3

.text
start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack_bottom,a7			*  A7 := スタックの底
		DOS	_GETPDB
		movea.l	d0,a0				*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : bit0:-f
							*         bit1:-i
							*         bit2:-r/-R
							*         bit3:-v
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		beq	decode_opt_done
decode_opt_loop2:
		cmp.b	#'f',d0
		beq	set_option_f

		cmp.b	#'i',d0
		beq	set_option_i

		moveq	#FLAG_r,d1
		cmp.b	#'r',d0
		beq	set_option

		cmp.b	#'R',d0
		beq	set_option

		moveq	#FLAG_v,d1
		cmp.b	#'v',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

set_option_f:
		bset	#FLAG_f,d5
		bclr	#FLAG_i,d5
		bra	set_option_done

set_option_i:
		bclr	#FLAG_f,d5
		bset	#FLAG_i,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
	*
	*  標準入力が端末であるかどうかを調べておく
	*
		moveq	#0,d0				*  標準入力は
		bsr	is_chrdev			*  キャラクタデバイス
		sne	stdin_is_terminal
	*
	*  処理開始
	*
		tst.l	d7
		beq	too_few_args

		moveq	#0,d6				*  D6.W : エラー・コード
rm_loop:
		movea.l	a0,a1
		bsr	strfor1
		move.l	a0,-(a7)			*  次の引数のアドレスをプッシュ
		movea.l	a1,a0
		bsr	strip_excessive_slashes
		bsr	remove				*  引数を処理
		movea.l	(a7)+,a0
		subq.l	#1,d7				*  引数の数だけ
		bne	rm_loop				*  繰り返し
exit_program:
	*
	*  終了
	*
		move.w	d6,-(a7)
		DOS	_EXIT2
****************
too_few_args:
		lea	msg_too_few_args(pc),a0
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
		moveq	#3,d6
		bra	exit_program
*****************************************************************
* remove - ファイルを削除する
*
* CALL
*      A0     ファイル名の先頭アドレス
*
* RETURN
*      D1-D3/A1-A3  破壊
*      D0.L   ファイルまたはディレクトリが存在し，それを削除したなら 0
*****************************************************************
remove_pathbuf = -((((MAXPATH+1)+1)>>1)<<1)
remove_filesbuf = remove_pathbuf-(((STATBUFSIZE+1)>>1)<<1)
remove_autosize = -remove_filesbuf

remove_recurse_stacksize	equ	remove_autosize+4*6	* 4*6 ... D2/A0/A2/A3/A6/PC


LEAVE_DIR	macro
		unlk	a6
		subq.l	#1,d3
		endm


remove:
		moveq	#0,d3				*  D3.L : ディレクトリの深さ
		movea.l	a0,a1
		move.b	(a0),d0
		beq	remove_no_drive

		cmpi.b	#':',1(a1)
		bne	remove_no_drive

		tst.b	2(a1)
		beq	cannot_remove

		addq.l	#2,a1
remove_no_drive:
		cmpi.b	#'/',(a1)
		beq	remove_abs

		cmpi.b	#'\',(a1)
		bne	remove_not_abs
remove_abs:
		tst.b	1(a1)
		beq	cannot_remove

		addq.l	#1,a1
remove_not_abs:
		bsr	isreldir
		beq	cannot_remove
remove_1:
		bsr	lstat
		bpl	remove_entry_1

		btst	#FLAG_f,d5
		bne	remove_return
remove_entry:
		tst.l	d0
		bmi	perror
remove_entry_1:
		btst	#MODEBIT_DIR,d0
		bne	remove_directory
remove_file:
		bsr	confirm_file
		bne	remove_return_false

		bsr	verbose
		move.w	#MODEVAL_ARC,-(a7)
		move.l	a0,-(a7)
		DOS	_CHMOD
		DOS	_DELETE
		addq.l	#6,a7
		bra	remove_done

remove_directory:
		btst	#FLAG_r,d5
		beq	it_is_directory

		addq.l	#1,d3				*  ディレクトリの深さをインクリメント
		cmp.l	#MAXRECURSE,d3
		bhi	dir_too_deep

		link	a6,#remove_filesbuf
		move.l	a0,-(a7)
		movea.l	a0,a1
		lea	dos_wildcard_all(pc),a2
		lea	remove_pathbuf(a6),a0
		bsr	cat_pathname
		movea.l	a0,a2				*  A2:検索パス名, A3:検索パス名のファイル名部
		movea.l	(a7)+,a0
		bmi	remove_directory_too_long_path

		move.l	a3,d0
		sub.l	a2,d0
		cmp.l	#MAXHEAD,d0
		bhi	remove_directory_too_long_path

		st	d2
		move.w	#MODEVAL_ALL,-(a7)		*  すべてのエントリを検索する
		move.l	a2,-(a7)
		pea	remove_filesbuf(a6)
		DOS	_FILES
		lea	10(a7),a7
		sf	d1
remove_directory_contents_loop:
		tst.l	d0
		bmi	do_remove_directory

		lea	remove_filesbuf+ST_NAME(a6),a1
		bsr	isreldir				*  . と .. は
		beq	remove_directory_contents_continue	*  無視

		tst.b	d1
		bne	remove_directory_contents_2
		*
		*  . と .. 以外のエントリが初めて見つかった．
		*  ということは，すなわちこのディレクトリは空ではない．
		*  -i が指定されているなら，このディレクトリ下に進むかどうかを問い合わせる．
		*
		movem.l	a2-a3,-(a7)
		lea	msg_enter(pc),a3
		bsr	confirm_dir
		movem.l	(a7)+,a2-a3
		bne	remove_directory_return_false
remove_directory_contents_2:
		movem.l	d2/a0/a2-a3,-(a7)
		movea.l	a3,a0
		bsr	strcpy
		movea.l	a2,a0
		bsr	lstat
		bsr	remove_entry			*  再帰！  1回あたり164バイトのスタックを消費する
		movem.l	(a7)+,d2/a0/a2-a3
		st	d1
		tst.l	d0
		beq	remove_directory_contents_continue

		sf	d2
remove_directory_contents_continue:
		pea	remove_filesbuf(a6)
		DOS	_NFILES
		addq.l	#4,a7
		bra	remove_directory_contents_loop

do_remove_directory:
		LEAVE_DIR
		moveq	#-21,d0				*  D0.L := EDIRNOTEMPTY
		tst.b	d2				*  ディレクトリの中に削除しなかったものが残っているなら
		beq	perror				*  どうせ削除できないのだから，confirm せずにエラーとして先に進む．

		lea	msg_remove(pc),a3
		bsr	confirm_dir
		bne	remove_return_false

		bsr	verbose
		move.l	a0,-(a7)
		DOS	_RMDIR
		addq.l	#4,a7
remove_done:
		tst.l	d0
		bmi	perror
remove_return:
		moveq	#0,d0
		rts

cannot_remove:
		moveq	#EBADNAME,d0
		bra	perror

it_is_directory:
		lea	msg_it_is_directory(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	remove_return_false

remove_directory_too_long_path:
		lea	msg_too_long_pathname(pc),a2
		bsr	werror_myname_word_colon_msg
remove_directory_return_false:
		LEAVE_DIR
remove_return_false:
		moveq	#-1,d0
		rts

dir_too_deep:
		lea	msg_dir_too_deep(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	remove_return_false
*****************************************************************
confirm_file:
		lea	msg_remove(pc),a3
		st	d1

		*  標準入力が端末ならば，ボリューム・ラベル，読み込み専用，
		*  隠し，システムのどれかの属性ビットがONである場合，問い合わせる

		tst.b	stdin_is_terminal
		beq	confirm_i

		movem.l	d0,-(a7)
		and.b	#(MODEVAL_VOL|MODEVAL_RDO|MODEVAL_HID|MODEVAL_SYS),d0
		movem.l	(a7)+,d0
		beq	confirm_i
		bra	confirm
****************
confirm_dir:
		lea	msg_directory(pc),a2
		sf	d1
****************
confirm_i:
		btst	#FLAG_i,d5
		beq	confirm_yes
confirm:
		btst	#FLAG_f,d5
		bne	confirm_yes

		bsr	werror_myname
		move.l	a0,-(a7)
		tst.b	d1
		beq	confirm_4

		btst	#MODEBIT_VOL,d0
		beq	confirm_1

		lea	msg_volumelabel(pc),a0
		bsr	werror
		bra	confirm_5

confirm_1:
		lea	msg_file(pc),a2
		btst	#MODEBIT_RDO,d0
		beq	confirm_2

		lea	msg_readonly(pc),a0
		bsr	werror
confirm_2:
		btst	#MODEBIT_HID,d0
		beq	confirm_3

		lea	msg_hidden(pc),a0
		bsr	werror
confirm_3:
		btst	#MODEBIT_SYS,d0
		beq	confirm_4

		lea	msg_system(pc),a0
		bsr	werror
confirm_4:
		movea.l	a2,a0
		bsr	werror
confirm_5:
		movea.l	(a7),a0
		bsr	werror
		movea.l	a3,a0
		bsr	werror
		lea	getsbuf(pc),a0
		move.b	#GETSLEN,(a0)
		move.l	a0,-(a7)
		DOS	_GETS
		addq.l	#4,a7
		bsr	werror_newline
		move.b	1(a0),d0
		beq	confirm_6

		move.b	2(a0),d0
confirm_6:
		movea.l	(a7)+,a0
confirm_return:
		cmp.b	#'y',d0
		rts

confirm_yes:
		moveq	#'y',d0
		bra	confirm_return
*****************************************************************
verbose:
		btst	#FLAG_v,d5
		beq	verbose_return

		move.l	a0,-(a7)
		DOS	_PRINT
		pea	msg_newline(pc)
		DOS	_PRINT
		addq.l	#8,a7
verbose_return:
		rts
*****************************************************************
lstat:
		move.w	#-1,-(a7)			*  ファイルの属性を得る．
		move.l	a0,-(a7)			*  ファイルがシンボリック・リンクである
		DOS	_CHMOD				*  場合は，リンク自体の属性を得る．
		addq.l	#6,a7				*  そのためには CHMOD で良い．
		tst.l	d0				*  （lndrv 1.0 への対応）
		rts
*****************************************************************
isreldir:
		cmpi.b	#'.',(a1)
		bne	isreldir_return

		tst.b	1(a1)
		beq	isreldir_return

		cmpi.b	#'.',1(a1)
		bne	isreldir_return

		tst.b	2(a1)
isreldir_return:
		rts
*****************************************************************
is_chrdev:
		movem.l	d0,-(a7)
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		movem.l	(a7)+,d0
		rts
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_newline:
		move.l	a0,-(a7)
		lea	msg_newline(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	msg_colon(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		movea.l	(a7)+,a0
		bsr	werror_newline
		moveq	#2,d6
		rts
*****************************************************************
perror:
		movem.l	d0/a2,-(a7)
		not.l	d0		* -1 -> 0, -2 -> 1, ...
		cmp.l	#25,d0
		bls	perror_2

		moveq	#0,d0
perror_2:
		lea	perror_table(pc),a2
perror_3:
		lsl.l	#1,d0
		move.w	(a2,d0.l),d0
		lea	sys_errmsgs(pc),a2
		lea	(a2,d0.w),a2
		bsr	werror_myname_word_colon_msg
		movem.l	(a7)+,d0/a2
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## rm 1.0 ##  Copyright(C)1992 by Itagaki Fumihiko',0

.even
perror_table:
	dc.w	msg_error-sys_errmsgs			*   0 ( -1)
	dc.w	msg_nofile-sys_errmsgs			*   1 ( -2)	CHMOD,DELETE,RMDIR
	dc.w	msg_nofile-sys_errmsgs			*   2 ( -3)	CHMOD,DELETE,RMIDR
	dc.w	msg_error-sys_errmsgs			*   3 ( -4)
	dc.w	msg_error-sys_errmsgs			*   4 ( -5)
	dc.w	msg_error-sys_errmsgs			*   5 ( -6)
	dc.w	msg_error-sys_errmsgs			*   6 ( -7)
	dc.w	msg_error-sys_errmsgs			*   7 ( -8)
	dc.w	msg_error-sys_errmsgs			*   8 ( -9)
	dc.w	msg_error-sys_errmsgs			*   9 (-10)
	dc.w	msg_error-sys_errmsgs			*  10 (-11)
	dc.w	msg_error-sys_errmsgs			*  11 (-12)
	dc.w	msg_bad_name-sys_errmsgs		*  12 (-13)	CHMOD,DELETE,RMDIR
	dc.w	msg_error-sys_errmsgs			*  13 (-14)
	dc.w	msg_bad_drive-sys_errmsgs		*  14 (-15)	CHMOD,DELETE,RMDIR
	dc.w	msg_current-sys_errmsgs			*  15 (-16)	RMDIR
	dc.w	msg_error-sys_errmsgs			*  16 (-17)
	dc.w	msg_error-sys_errmsgs			*  17 (-18)
	dc.w	msg_write_disabled-sys_errmsgs		*  18 (-19)	DELETE,RMDIR?
	dc.w	msg_error-sys_errmsgs			*  19 (-20)
	dc.w	msg_not_empty-sys_errmsgs		*  20 (-21)	RMDIR
	dc.w	msg_error-sys_errmsgs			*  21 (-22)
	dc.w	msg_error-sys_errmsgs			*  22 (-23)
	dc.w	msg_error-sys_errmsgs			*  23 (-24)
	dc.w	msg_error-sys_errmsgs			*  24 (-25)
	dc.w	msg_error-sys_errmsgs			*  25 (-26)

sys_errmsgs:
msg_error:		dc.b	'エラー',0
msg_nofile:		dc.b	'このようなファイルやディレクトリはありません',0
msg_bad_name:		dc.b	'名前が無効です',0
msg_bad_drive:		dc.b	'ドライブの指定が無効です',0
msg_current:		dc.b	'カレント・ディレクトリですので削除できません',0
msg_write_disabled:	dc.b	'削除は許可されていません',0
msg_not_empty:		dc.b	'ディレクトリが空でないので削除できません',0

msg_myname:			dc.b	'rm'
msg_colon:			dc.b	': ',0
msg_no_memory:			dc.b	'メモリが足りません',CR,LF,0
msg_illegal_option:		dc.b	'不正なオプション -- ',0
msg_too_few_args:		dc.b	'引数が足りません',0
msg_too_long_pathname:		dc.b	'パス名が長過ぎます',0
msg_it_is_directory:		dc.b	'ディレクトリです',0
msg_readonly:			dc.b	'書き込み禁止',0
msg_hidden:			dc.b	'隠し',0
msg_system:			dc.b	'システム',0
msg_file:			dc.b	'ファイル“',0
msg_volumelabel:		dc.b	'ボリュームラベル“',0
msg_directory:			dc.b	'ディレクトリ“',0
msg_remove:			dc.b	'”を削除しますか？',0
msg_enter:			dc.b	'”は空ではありません．中に進みますか？',0
msg_dir_too_deep:		dc.b	'ディレクトリが深過ぎて処理できません',0
msg_usage:			dc.b	CR,LF,'使用法:  rm [-firvR] [-] <ファイル> ...'
msg_newline:			dc.b	CR,LF,0
dos_wildcard_all:		dc.b	'*.*',0
*****************************************************************
.bss
“”
.even
getsbuf:		ds.b	2+GETSLEN+1
stdin_is_terminal:	ds.b	1
.even
			ds.b	256+remove_recurse_stacksize*(MAXRECURSE+1)
			*  必要なスタック量は，再帰の度に消費されるスタック量と
			*  その回数とで決まる．
			*  その他にマージンを含めたミニマム量として 256バイトを確保しておく．
			*  このプログラムでは 256バイトあれば充分である．
.even
stack_bottom:
*****************************************************************

.end start
