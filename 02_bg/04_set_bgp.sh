#!/bin/bash

set -uex

. include/gb.sh

TILE_SIZE=10	# 16バイト

# エントリアドレスは自由に使えるROM領域の先頭(0x0150)から
# タイルを配置した16バイト先のアドレスになる
ENTRY_ADDR=$(echo "${GB_ROM_FREE_BASE}+${TILE_SIZE}" | bc)

VRAM_TILE_DATA_BASE=8000

BGP_VAL=e4

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

	# LCDを再開させる
	lr35902_copy_to_regA_from_ioport $GB_IO_LCDC
	lr35902_set_bitN_of_reg 7 regA
	lr35902_copy_to_ioport_from_regA $GB_IO_LCDC

	# BGP設定
	lr35902_set_reg regA $BGP_VAL
	lr35902_copy_to_ioport_from_regA $GB_IO_BGP

	# 無限halt
	infinite_halt
}

# 全てnopの割り込みベクタ生成
gb_all_nop_vector_table

# カートリッジヘッダ生成
gb_cart_header_no_title $ENTRY_ADDR

# main処理
main >main.o
cat main.o

# 32KBに満たない分を0で埋める
main_size=$(stat -c '%s' main.o)
dd if=/dev/zero bs=1 \
   count=$((GB_ROM_SIZE - GB_VECT_SIZE - GB_HEAD_SIZE - main_size))
