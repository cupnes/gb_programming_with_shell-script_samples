#!/bin/bash

set -uex

. include/gb.sh

TILE_SIZE=10	# 16バイト

# エントリアドレスは自由に使えるROM領域の先頭(0x0150)から
# タイルを配置した16バイト先のアドレスになる
ENTRY_ADDR=$(echo "${GB_ROM_FREE_BASE}+${TILE_SIZE}" | bc)

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
