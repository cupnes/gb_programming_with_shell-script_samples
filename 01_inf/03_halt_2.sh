#!/bin/bash

set -uex

. include/gb.sh

PROG_SIZE=4

# 全てnopの割り込みベクタ生成
gb_all_nop_vector_table

# カートリッジヘッダ生成
gb_cart_header_no_title ${GB_ROM_FREE_BASE}

# 無限halt
infinite_halt

# 32KBに満たない分を0で埋める
dd if=/dev/zero bs=1 \
   count=$((GB_ROM_SIZE - GB_VECT_SIZE - GB_HEAD_SIZE - PROG_SIZE))
