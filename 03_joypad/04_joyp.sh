#!/bin/bash

set -uex

. include/gb.sh

TILE_SIZE=10	# 16バイト

# エントリアドレスは自由に使えるROM領域の先頭(0x0150)から
# タイルを配置した16バイト先のアドレスになる
ENTRY_ADDR=$(echo "${GB_ROM_FREE_BASE}+${TILE_SIZE}" | bc)

VRAM_TILE_DATA_BASE=8000
VRAM_BG_TILE_MAP_BASE=9800
VRAM_BG_TILE_MAP_END=9bff

BGP_VAL=e4

manual_scroll() {
	# ジョイパッド入力取得(十字キー)
	## 十字キーの入力を取得するように設定
	lr35902_copy_to_regA_from_ioport $GB_IO_JOYP
	lr35902_set_bitN_of_reg 5 regA
	lr35902_res_bitN_of_reg 4 regA
	lr35902_copy_to_ioport_from_regA $GB_IO_JOYP
	## 入力取得(ノイズ除去のため2回読む)
	lr35902_copy_to_regA_from_ioport $GB_IO_JOYP
	lr35902_copy_to_regA_from_ioport $GB_IO_JOYP
	## ビット反転(押下中のキーのビットが1になる)
	lr35902_complement_regA
	## レジスタBへ格納
	lr35902_copy_to_from regB regA
}

main() {
	# 自由に使える領域の先頭(0x0150)にタイルデータを追加する
	cat tile.2bpp

	# 割り込み無効化
	lr35902_disable_interrupts

	# Vブランク期間を待つ
	gb_wait_for_vblank_to_start

	# LCD設定&LCD無効化
	lr35902_set_reg regA 51
	lr35902_copy_to_ioport_from_regA $GB_IO_LCDC

	# タイルデータをVRAMのタイルデータ領域(0x8000)へロードする
	lr35902_set_reg regDE $GB_ROM_FREE_BASE
	lr35902_set_reg regHL $VRAM_TILE_DATA_BASE
	lr35902_set_reg regC $TILE_SIZE
	(
		lr35902_copy_to_from regA ptrDE
		lr35902_copyinc_to_ptrHL_from_regA
		lr35902_inc regDE
		lr35902_dec regC
	) >main.1.o
	cat main.1.o
	local sz_1=$(stat -c '%s' main.1.o)
	lr35902_rel_jump_with_cond NZ $(two_comp_d $((sz_1+2)))

	# 背景用タイルマップ(0x9800-9BFF)をタイル番号0で初期化する
	## 最終アドレス上位8ビット(0x9b)
	local end_th=$(echo $VRAM_BG_TILE_MAP_END | cut -c1-2)
	## 最終アドレス下位8ビット(0xff)
	local end_bh=$(echo $VRAM_BG_TILE_MAP_END | cut -c3-4)
	lr35902_set_reg regHL $VRAM_BG_TILE_MAP_BASE
	(
		(
			# 0x00をレジスタHLの指す先へ設定し、HLをインクリメント
			lr35902_clear_reg regA
			lr35902_copyinc_to_ptrHL_from_regA

			# レジスタHと最終アドレス上位8ビットを比較
			lr35902_copy_to_from regA regH
			lr35902_compare_regA_and $end_th
		) >main.2.o
		cat main.2.o
		local sz_2=$(stat -c '%s' main.2.o)
		# レジスタH != 0x9b なら
		# main.2.oのサイズ(+相対ジャンプ命令のサイズ)分戻る
		lr35902_rel_jump_with_cond NZ $(two_comp_d $((sz_2+2)))

		# レジスタLと最終アドレス下位8ビットを比較
		lr35902_copy_to_from regA regL
		lr35902_compare_regA_and $end_bh
	) >main.3.o
	cat main.3.o
	local sz_3=$(stat -c '%s' main.3.o)
	# レジスタL != 0xff なら
	# main.3.oのサイズ(+相対ジャンプ命令のサイズ)分戻る
	lr35902_rel_jump_with_cond NZ $(two_comp_d $((sz_3+2)))

	# LCDを再開させる
	lr35902_copy_to_regA_from_ioport $GB_IO_LCDC
	lr35902_set_bitN_of_reg 7 regA
	lr35902_copy_to_ioport_from_regA $GB_IO_LCDC

	# BGP設定
	lr35902_set_reg regA $BGP_VAL
	lr35902_copy_to_ioport_from_regA $GB_IO_BGP

	# Vブランク割り込み有効化
	lr35902_copy_to_regA_from_ioport $GB_IO_IE
	lr35902_set_bitN_of_reg 0 regA
	lr35902_copy_to_ioport_from_regA $GB_IO_IE

	# 割り込み有効化
	lr35902_enable_interrupts

	(
		# 割り込みがあるまでhalt
		lr35902_halt

		# 手動画面スクロール
		manual_scroll
	) >main.4.o
	cat main.4.o
	local sz_4=$(stat -c '%s' main.4.o)
	lr35902_rel_jump $(two_comp_d $((sz_4+2)))
}

# 割り込みベクタ生成
## 0x0000 - 0x003F(64バイト)は0x00(nop)で埋める
dd if=/dev/zero bs=1 count=64
## 0x0040(Vブランク)に割り込みからリターンする命令(reti)(1バイト)を配置
lr35902_ei_and_ret
## 0x0041 - 0x00FF(191バイト)は0x00(nop)で埋める
dd if=/dev/zero bs=1 count=191

# カートリッジヘッダ生成
gb_cart_header_no_title $ENTRY_ADDR

# main処理
main >main.o
cat main.o

# 32KBに満たない分を0で埋める
main_size=$(stat -c '%s' main.o)
dd if=/dev/zero bs=1 \
   count=$((GB_ROM_SIZE - GB_VECT_SIZE - GB_HEAD_SIZE - main_size))
