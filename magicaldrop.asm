################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Cade McNelly, 1011958419
# Student 2: Jay Bharat Mehta, 1011744230
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       TODO
# - Unit height in pixels:      TODO
# - Display width in pixels:    TODO
# - Display height in pixels:   TODO
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

##############################################################################
# 01 | Constants and coordinate conventions
##############################################################################
# Board coordinates are zero-based and exclude the border. Frame and player
# coordinates are logical screen cells. draw_unit scales those cells to bitmap units.
# The bitmap stride is 64 addressable units. The 9 x 16 frame at scale 3 occupies
# 27 x 48 units. Match the simulator's stride and base address to these constants.

.eqv PLAYFIELD_COLS  7                  # Board width in logical cells.
.eqv PLAYFIELD_ROWS  14                 # Board height in logical cells.

.eqv FRAME_COLS 9                       # Frame width, including both side borders.
.eqv FRAME_ROWS 16                      # Frame height, including top and bottom borders.

.eqv BITMAP_SIZE_UNITS 64               # Addressable bitmap units per row.
.eqv CELL_SCALE 3                       # Draw each logical cell as a 3 x 3 bitmap block.

# Colour IDs are palette indices. The board uses CELL_EMPTY and the four bubble colours.
.eqv CELL_EMPTY      0
.eqv CELL_RED        1
.eqv CELL_GREEN      2
.eqv CELL_BLUE       3
.eqv CELL_YELLOW     4
.eqv CELL_FRAME      5
.eqv CELL_PLAYER     6

# ASCII codes for the game controls.
.eqv KEY_A           0x61
.eqv KEY_D           0x64
.eqv KEY_S           0x73
.eqv KEY_W           0x77
.eqv KEY_Q           0x71

# Byte offsets into player_state.
.eqv PLAYER_COL_OFFSET          0
.eqv PLAYER_SCORE_OFFSET        4
.eqv PLAYER_HELD_COLOUR_OFFSET  8
.eqv PLAYER_HELD_COUNT_OFFSET   12
.eqv PLAYER_STATE_SIZE          16

.eqv PLAYER_ROW                 14      # Player's logical screen row, inside the bottom border.
.eqv MOVES_PER_WAVE             10      # Counted actions before advancing the board.

##############################################################################
# 02 | Data layout
##############################################################################
# Device addresses and the RGB palette come first, followed by mutable state.

    .data

ADDR_DSPL:
    .word 0x10008000                    # First word of the bitmap framebuffer.

ADDR_KBRD:
    .word 0xffff0000                    # Keyboard status at +0, character data at +4.

# Palette words are indexed by colour ID and encoded as 0x00RRGGBB.
bubble_palette:
    .word 0x00000000                    # CELL_EMPTY: black.
    .word 0x00ff0000                    # CELL_RED.
    .word 0x0000ff00                    # CELL_GREEN.
    .word 0x000000ff                    # CELL_BLUE.
    .word 0x00ffff00                    # CELL_YELLOW.
    .word 0x00777777                    # CELL_FRAME: grey.
    .word 0x00ff00ba                    # CELL_PLAYER: pink.

    .align 2                            # Align the following words to a 4-byte boundary.

##############################################################################
# 03 | Player and game state
##############################################################################
# player_state names the base of the four-word record. The field labels also allow
# direct access. State offsets above are byte offsets within this record.

player_state:
player_col:
    .word 3                             # Start in board column 3 of 0-6.

player_score:
    .word 0

held_colour:                            # Alias for player_state + PLAYER_HELD_COLOUR_OFFSET.
    .word CELL_EMPTY                    # One colour ID for the whole held stack.

held_count:
    .word 0                             # Number of held bubbles, initially zero.

# Game-wide counters and flags.
moves_since_last_wave:
    .word 0                             # Actions counted since the most recent wave.

game_over:
    .word 0                             # 0 = running, 1 = a bubble reached the bottom row.

##############################################################################
# 04 | Board storage and match markers
##############################################################################
# Both arrays are row-major: index = row * PLAYFIELD_COLS + column.
# board stores a four-byte colour ID per cell. match_marks stores a one-byte
# flag at the same index (0 = unmarked, 1 = marked).

    .align 2

board:
    .space 392                          # 14 rows x 7 columns x 4 bytes.

match_marks:
    .space 98                           # One byte per board cell, in the same order as board.

##############################################################################
# 05 | Startup
##############################################################################
# Initialize the board, paint the frame and scene, then enter the input loop.

    .text
    .globl main

main:
    jal initialize_board                # Clear the board and seed its starting rows.
    nop

    jal draw_frame                      # Draw the static border.
    nop

    jal draw_board                      # Draw the current bubble cells inside the border.
    nop

    jal draw_player                     # Overlay the player on the board.
    nop

    j game_loop                         # Enter the main loop.
    nop

##############################################################################
# 06 | Frame rendering
##############################################################################
# Draw full rows along the top and bottom and just the side edges in between.
# draw_frame takes no arguments and draws through draw_unit.

draw_frame:
    addi $sp, $sp, -16                  # Frame slots save $ra and $s0-$s2 across calls.
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)
    sw   $s2, 0($sp)

    li   $s0, 0                         # $s0 = current logical screen row.
    li   $s1, CELL_FRAME                # $s1 = border colour ID.
    li   $s2, 0                         # $s2 = current column when drawing a full row.

frame_row_loop:
    beq $s0, $zero, frame_full_row      # Row 0 is the top border.

    li   $t0, FRAME_ROWS
    addi $t0, $t0, -1                   # $t0 = bottom border row (FRAME_ROWS - 1).

    beq $s0, $t0, frame_full_row        # Fill the bottom border just like the top.

    move $a0, $s0                       # $a0 = current screen row.
    li   $a1, 0                         # $a1 = left border column.
    move $a2, $s1                       # $a2 = border colour ID.
    jal  draw_unit
    nop

    move $a0, $s0                       # $a0 = same screen row.
    li   $a1, FRAME_COLS
    addi $a1, $a1, -1                   # $a1 = right border column (FRAME_COLS - 1).
    move $a2, $s1                       # $a2 = border colour ID.
    jal  draw_unit
    nop

    j frame_next_row
    nop

frame_full_row:
    move $a0, $s0                       # $a0 = top or bottom border row.
    move $a1, $s2                       # $a1 = current column within the full row.
    move $a2, $s1                       # $a2 = border colour ID.
    jal draw_unit
    nop

    addiu $s2, $s2, 1                   # Advance to the next column.
    li    $t0, FRAME_COLS
    blt   $s2, $t0, frame_full_row
    nop

frame_next_row:
    li    $s2, 0                        # Reset the full-row column for later use.
    addiu $s0, $s0, 1                   # Advance to the next logical screen row.

    li  $t0, FRAME_ROWS
    blt $s0, $t0, frame_row_loop
    nop

frame_finished:

    lw   $s2, 0($sp)
    lw   $s1, 4($sp)
    lw   $s0, 8($sp)
    lw   $ra, 12($sp)                   # Release the 16-byte frame before returning.
    addi $sp, $sp, 16

    jr $ra
    nop

##############################################################################
# 07 | Board initialization and random rows
##############################################################################
# initialize_board clears every board word and populates the first four rows.

initialize_board:
    addiu $sp, $sp, -12                 # Save the return address and two working registers.
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    la $s0, board                       # $s0 = cursor over board words.
    li $s1, 98                          # $s1 = board cells left to clear.

clear_board_loop:
    sw $zero, 0($s0)                    # Set the current board cell to CELL_EMPTY.
    addiu $s0, $s0, 4                   # Advance by one word (4 bytes).
    addiu $s1, $s1, -1                  # One fewer cell left to clear.

    bgtz $s1, clear_board_loop
    nop

    li $s0, 0                           # Reuse $s0 as the row number, starting at row 0.

initialize_rows_loop:
    move $a0, $s0                       # $a0 = board row to populate.
    jal fill_bubble_row
    nop

    addiu $s0, $s0, 1
    li $t0, 4                           # Seed board rows 0-3.

    blt $s0, $t0, initialize_rows_loop
    nop

    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addiu $sp, $sp, 12

    jr $ra
    nop

# fill_bubble_row takes a zero-based board row in $a0.
# $s0 walks its cells and $s1 counts columns left to fill.
fill_bubble_row:

    addiu $sp, $sp, -8                  # Save $s0 and $s1 for this leaf routine.
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    li $t0, PLAYFIELD_COLS              # $t0 = cells per board row.
    mul $t1, $a0, $t0                   # $t1 = cell index of row's first column.
    sll $t1, $t1, 2                     # Convert the cell index to a byte offset (x4).

    la $s0, board
    addu $s0, $s0, $t1                  # $s0 = current board cell address.

    li $s1, PLAYFIELD_COLS              # $s1 = columns left to fill.

fill_bubble_loop:
    li $v0, 42                          # Random integer range syscall.
    li $a0, 0                           # $a0 = random generator ID.
    li $a1, 4                           # $a1 = exclusive upper bound.
    syscall                             # Returns a value in $a0 in the range 0-3.

    addiu $t0, $a0, 1                   # $t0 = bubble colour ID in the range 1-4.

    sw $t0, 0($s0)                      # Write the colour ID to board memory.

    addiu $s0, $s0, 4                   # Advance to the next board word.
    addiu $s1, $s1, -1                  # One fewer column left to fill.

    bgtz $s1, fill_bubble_loop
    nop

    lw $s1, 0($sp)
    lw $s0, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop

##############################################################################
# 08 | Board rendering
##############################################################################
# draw_board walks every board cell, including empty cells. Adding one to
# the logical row and column puts board cell (0, 0) inside the frame.

draw_board:

    addiu $sp, $sp, -16                 # Save $ra plus row, column, and board cursor registers.
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    la $s2, board                       # $s2 = cursor over board words in row-major order.
    li $s0, 0                           # $s0 = logical board row.

draw_board_row:
    li $s1, 0                           # $s1 = logical board column, reset for each row.

draw_board_col:
    lw $a2, 0($s2)                      # $a2 = current bubble colour ID (or CELL_EMPTY).

    addiu $a0, $s0, 1                   # $a0 = screen row after the top border offset.
    addiu $a1, $s1, 1                   # $a1 = screen column after the left border offset.

    jal draw_unit
    nop

    addiu $s2, $s2, 4                   # Advance the board cursor by one word.
    addiu $s1, $s1, 1                   # Advance the logical column.

    li $t0, PLAYFIELD_COLS
    blt $s1, $t0, draw_board_col
    nop

    addiu $s0, $s0, 1                   # Advance the logical row.

    li $t0, PLAYFIELD_ROWS
    blt $s0, $t0, draw_board_row
    nop

    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addiu $sp, $sp, 16

    jr $ra
    nop

##############################################################################
# 09 | Wave advancement and bottom-row check
##############################################################################
# advance_bubble_rows copies from bottom to top because source and destination
# overlap. This order preserves each source cell until it has been copied.

advance_bubble_rows:

    addiu $sp, $sp, -8
    sw $ra, 4($sp)

    la $t0, board                       # $t0 = board base.
    li $t1, PLAYFIELD_ROWS              # $t1 = board row count.
    li $t2, PLAYFIELD_COLS              # $t2 = board column count.

    mul $t3, $t1, $t2                   # $t3 = total number of cells.
    addiu $t3, $t3, -1                  # $t3 = zero-based index of the last cell.
    sll $t3, $t3, 2                     # Convert the last index to a byte offset.
    addu $t4, $t0, $t3                  # $t4 = destination cursor, starting at the last cell.

    sll $t5, $t2, 2                     # $t5 = board row stride in bytes (7 words x 4).
    subu $t6, $t4, $t5                  # $t6 = source cursor, one row above destination.

    addiu $t7, $t1, -1                  # $t7 = source rows to move.
    mul $t7, $t7, $t2                   # $t7 = cells left to copy.

advance_bubble_rows_loop:
    lw $t8, 0($t6)                      # $t8 = colour ID from the source cell.
    sw $t8, 0($t4)                      # Store it one row below its original position.

    addiu $t6, $t6, -4                  # Step backward to the previous source word.
    addiu $t4, $t4, -4                  # Step backward to the previous destination word.
    addiu $t7, $t7, -1                  # One fewer cell left to copy.

    bgtz $t7, advance_bubble_rows_loop
    nop

    li $a0, 0                           # $a0 = top board row after moving existing rows.
    jal fill_bubble_row
    nop

    jal draw_board                      # Refresh the shifted board.
    nop

    lw $ra, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop

# check_game_over inspects every column in the last board row.
# It sets game_over on the first occupied cell and leaves the existing flag otherwise.
check_game_over:

    la $t0, board                       # $t0 = board base.

    li $t1, PLAYFIELD_ROWS
    addiu $t1, $t1, -1                  # $t1 = last logical board row, row 13.

    li $t2, PLAYFIELD_COLS
    mul $t1, $t1, $t2                   # $t1 = cell index of the first cell in the last row.
    sll $t1, $t1, 2                     # Convert that index to a byte offset.

    addu $t0, $t0, $t1                  # $t0 = address of the first cell in the bottom row.

    li $t2, PLAYFIELD_COLS              # $t2 = columns left to check in that row.

check_game_over_loop:
    lw $t3, 0($t0)                      # $t3 = colour ID at the current bottom-row cell.

    bne $t3, $zero, game_over_reached   # Any occupied cell on this row sets game_over.
    nop

    addiu $t0, $t0, 4                   # Advance to the next bottom-row word.
    addiu $t2, $t2, -1

    bgtz $t2, check_game_over_loop
    nop

    jr $ra
    nop

game_over_reached:
    li $t3, 1
    sw $t3, game_over                   # Record game over in memory.

    jr $ra
    nop

##############################################################################
# 10 | Match detection, removal, and flood fill
##############################################################################
# detect_vertical_matches is the whole-board scanner. It resets the marker array
# and marks vertical triples. The current throw path uses a local trigger instead.

detect_vertical_matches:

    la $t0, match_marks                 # $t0 = cursor over the match-marker bytes.
    li $t1, 98                          # $t1 = marker bytes left to clear.

clear_match_marks_loop:
    sb $zero, 0($t0)                    # Reset this cell's match marker to unmarked.
    addiu $t0, $t0, 1                   # Advance by one byte.
    addiu $t1, $t1, -1

    bgtz $t1, clear_match_marks_loop
    nop

    la $t0, board                       # $t0 = base of the board's word array.
    la $t1, match_marks                 # $t1 = base of the byte array of match markers.

    li $t2, 0                           # $t2 = candidate starting row.

detect_match_row_loop:
    li $t3, 0                           # $t3 = candidate column, reset for each row.

detect_match_col_loop:
    li $t4, PLAYFIELD_COLS
    mul $t5, $t2, $t4                   # $t5 = index of the row's first cell.
    addu $t5, $t5, $t3                  # $t5 = candidate cell index (row x columns + column).

    sll $t6, $t5, 2                     # $t6 = board byte offset of the candidate cell.
    addu $t7, $t0, $t6                  # $t7 = address of the candidate board word.

    lw $t8, 0($t7)                      # $t8 = candidate colour ID.

    beq $t8, $zero, detect_match_next_col  # Empty cells cannot start a match.
    nop

    lw $t9, 28($t7)                     # $t9 = same-column cell one row below (+28 bytes).
    bne $t8, $t9, detect_match_next_col
    nop

    lw $t9, 56($t7)                     # $t9 = same-column cell two rows below (+56 bytes).
    bne $t8, $t9, detect_match_next_col
    nop

    addu $t7, $t1, $t5                  # $t7 = candidate marker address (one byte per cell).
    li $t9, 1

    sb $t9, 0($t7)                      # Mark the candidate cell.
    sb $t9, 7($t7)                      # Mark one row below (+7 marker bytes).
    sb $t9, 14($t7)                     # Mark two rows below (+14 marker bytes).

detect_match_next_col:
    addiu $t3, $t3, 1                   # Try the next column in the same starting row.

    li $t4, PLAYFIELD_COLS
    blt $t3, $t4, detect_match_col_loop
    nop

    addiu $t2, $t2, 1                   # Move down to the next candidate starting row.

    li $t4, PLAYFIELD_ROWS
    addiu $t4, $t4, -2                  # Exclusive limit: last legal start row is 11.

    blt $t2, $t4, detect_match_row_loop
    nop

    jr $ra
    nop

# remove_marked_bubbles clears every marked board word and consumes its byte marker.
# It returns the number cleared in $v0 and redraws if that count is nonzero.
remove_marked_bubbles:

    addiu $sp, $sp, -20                 # Save $ra and the four registers used across drawing.
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    la $s0, board                       # $s0 = cursor over board words.
    la $s1, match_marks                 # $s1 = cursor over marker bytes.

    li $s2, 98                          # $s2 = cells left to inspect.

    li $s3, 0                           # $s3 = number of removed bubbles.

remove_marked_loop:
    lbu $t0, 0($s1)                     # $t0 = marker for the current board cell.

    beq $t0, $zero, remove_marked_next  # Keep the board cell if its marker is clear.
    nop

    sw $zero, 0($s0)                    # Clear the marked board cell.
    sb $zero, 0($s1)                    # Consume the marker so it cannot affect a later throw.

    addiu $s3, $s3, 1                   # Increment the removal count.

remove_marked_next:
    addiu $s0, $s0, 4                   # Next board cell is one word away.

    addiu $s1, $s1, 1                   # Next marker is one byte away.

    addiu $s2, $s2, -1

    bgtz $s2, remove_marked_loop
    nop

    beq $s3, $zero, remove_marked_finished  # Skip the board redraw if no cells were removed.
    nop

    jal draw_board
    nop

remove_marked_finished:
    move $v0, $s3                       # $v0 = number of cleared cells.

    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20

    jr $ra
    nop

# process_neighbouring_matches marks a connected group without editing the board.
# Inputs: $a0 = board row, $a1 = board column, $a2 = seed colour ID.
# The caller supplies a matching seed. Each recursive call checks coordinates,
# colour, and visit state before allocating a frame and exploring four neighbours.
process_neighbouring_matches:

    # Unsigned comparisons reject negative coordinates as well as upper-bound overflow.
    sltiu $t0, $a0, PLAYFIELD_ROWS      # $t0 = 1 only for board rows 0-13 (unsigned check).
    beq   $t0, $zero, neighbour_done
    nop
    sltiu $t0, $a1, PLAYFIELD_COLS      # $t0 = 1 only for board columns 0-6.
    beq   $t0, $zero, neighbour_done
    nop

    li   $t0, PLAYFIELD_COLS
    mul  $t1, $a0, $t0                  # $t1 = index of the first cell in this row.
    addu $t1, $t1, $a1                  # $t1 = index of the current cell.

    la   $t2, board
    sll  $t3, $t1, 2                    # $t3 = board byte offset (cell index x 4).
    addu $t2, $t2, $t3                  # $t2 = address of the current board word.
    lw   $t4, 0($t2)                    # $t4 = colour stored in this board cell.
    bne  $t4, $a2, neighbour_done       # Stop this branch if the colour differs from the seed.
    nop

    la   $t2, match_marks
    addu $t2, $t2, $t1                  # $t2 = address of this cell's byte-sized marker.
    lbu  $t4, 0($t2)                    # $t4 = existing visit marker.
    bne  $t4, $zero, neighbour_done     # Stop this branch if a previous call visited this cell.
    nop

    li $t4, 1
    sb $t4, 0($t2)                      # Mark before recursing so neighbours cannot revisit it.

    addiu $sp, $sp, -16                 # Each visited cell gets its own saved register frame.
    sw    $ra, 12($sp)                  # Save the return address for this recursion level.
    sw    $s0, 8($sp)
    sw    $s1, 4($sp)
    sw    $s2, 0($sp)

    move $s0, $a0                       # $s0 = this cell's row across all four calls.
    move $s1, $a1                       # $s1 = this cell's column across all four calls.
    move $s2, $a2                       # $s2 = target colour across all four calls.

    addiu $a0, $s0, -1                  # Up: same column, previous row.
    move  $a1, $s1
    move  $a2, $s2
    jal   process_neighbouring_matches
    nop

    addiu $a0, $s0, 1                   # Down: same column, next row.
    move  $a1, $s1
    move  $a2, $s2
    jal   process_neighbouring_matches
    nop

    move  $a0, $s0
    addiu $a1, $s1, -1                  # Left: same row, previous column.
    move  $a2, $s2
    jal   process_neighbouring_matches
    nop

    move  $a0, $s0
    addiu $a1, $s1, 1                   # Right: same row, next column.
    move  $a2, $s2
    jal   process_neighbouring_matches
    nop

    lw    $s2, 0($sp)
    lw    $s1, 4($sp)
    lw    $s0, 8($sp)
    lw    $ra, 12($sp)
    addiu $sp, $sp, 16                  # Release this call's frame after all neighbours return.

# Base cases reach this return without having allocated a stack frame.
neighbour_done:
    jr $ra
    nop

##############################################################################
# 11 | Palette lookup and scaled bitmap drawing
##############################################################################
# get_colour($a0 = colour ID) returns a packed RGB word in $v0.

get_colour:
    la $t0, bubble_palette              # $t0 = first palette word.
    sll $t1, $a0, 2                     # $t1 = palette offset in bytes (colour ID x 4).
    add $t0, $t0, $t1                   # $t0 = address of the selected palette word.
    lw  $v0, 0($t0)                     # $v0 = packed RGB word for the caller.

    jr $ra
    nop

# draw_unit($a0 = logical row, $a1 = logical column, $a2 = colour ID)
# fills a CELL_SCALE x CELL_SCALE square in the bitmap.
draw_unit:
    addiu $sp, $sp, -16
    sw    $ra, 12($sp)                  # Preserve the link back to the drawing caller.
    sw    $a0, 8($sp)                   # Save the logical row before reusing $a0.
    sw    $a1, 4($sp)                   # Save the logical column across get_colour.

    move $a0, $a2                       # $a0 = palette index expected by get_colour.
    jal  get_colour
    nop

    lw   $t0, 8($sp)                    # $t0 = original logical screen row.
    lw   $t1, 4($sp)                    # $t1 = original logical screen column.
    li   $t2, BITMAP_SIZE_UNITS         # $t2 = number of addressable units across the bitmap.
    li   $t4, CELL_SCALE                # $t4 = width and height of one logical cell in bitmap units.

    # Top-left offset in bytes = 4 * ((row * scale) * bitmap width + column * scale).
    mul  $t0, $t0, $t4                  # $t0 = topmost bitmap row of the cell.
    mul  $t1, $t1, $t4                  # $t1 = leftmost bitmap column of the cell.
    mul  $t0, $t0, $t2                  # $t0 = first bitmap unit index in the scaled row.
    addu $t0, $t0, $t1                  # Add the scaled column to get the first unit's index.
    sll  $t0, $t0, 2                    # Convert bitmap unit index to byte offset (x4).

    lw   $t3, ADDR_DSPL                 # $t3 = base address of the bitmap.
    addu $t3, $t3, $t0                  # $t3 = left edge address of the current bitmap row.
    sll  $t2, $t2, 2                    # $t2 = bitmap row stride in bytes.
    move $t5, $t4                       # $t5 = number of bitmap rows left to fill.

draw_unit_row_loop:
    move $t6, $t3                       # $t6 = horizontal cursor for this bitmap row.
    move $t7, $t4                       # $t7 = bitmap units left to fill in this row.

draw_unit_col_loop:
    sw    $v0, 0($t6)                   # Write the packed RGB value returned in $v0.
    addiu $t6, $t6, 4                   # Move one unit right (one word).
    addiu $t7, $t7, -1                  # One fewer unit left in this row.
    bgtz  $t7, draw_unit_col_loop
    nop

    addu  $t3, $t3, $t2                 # Advance the row start by one bitmap row stride.
    addiu $t5, $t5, -1                  # One fewer bitmap row left to fill.
    bgtz  $t5, draw_unit_row_loop
    nop

    lw    $ra, 12($sp)
    addiu $sp, $sp, 16
    jr    $ra
    nop

##############################################################################
# 12 | Player and held-bubble overlay
##############################################################################
# draw_player reads player_col, held_count, and held_colour from memory.
# It draws using logical screen coordinates, including the frame offsets.

draw_player:

    addiu $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    # The legacy clear loop starts at row 16 and tests its limit after drawing a row.
    # With PLAYER_ROW set to 14, it clears row 16 once.
    li $s0, 16                          # $s0 = first row of the legacy holding-area clear pass.

draw_player_clear_row:
    li $s1, 0                           # $s1 = logical column, reset for each clear row.

draw_player_clear_col:
    move $a0, $s0                       # $a0 = logical screen row being cleared.
    addiu $a1, $s1, 1                   # $a1 = screen column inside the side borders.
    li $a2, CELL_EMPTY                  # $a2 = black, from the empty-cell palette entry.

    jal draw_unit
    nop

    addiu $s1, $s1, 1
    li $t0, PLAYFIELD_COLS
    blt $s1, $t0, draw_player_clear_col
    nop

    addiu $s0, $s0, 1                   # Advance the clear pass to the next logical screen row.
    li $t0, PLAYER_ROW
    addiu $t0, $t0, 1                   # $t0 = exclusive upper limit for the clear pass.
    blt $s0, $t0, draw_player_clear_row
    nop

    lw $s1, player_col                  # $s1 = player's zero-based board column.

    li $a0, PLAYER_ROW                  # $a0 = player's logical screen row (currently 14).
    addiu $a1, $s1, 1                   # $a1 = player's logical screen column (board column + 1).
    li $a2, CELL_PLAYER                 # $a2 = player colour ID.

    jal draw_unit
    nop

    lw $s2, held_count                  # $s2 = held bubbles left to draw.
    lw $s3, held_colour                 # $s3 = shared colour ID of the held stack.

    beq $s2, $zero, draw_player_finished
    nop

    beq $s3, $zero, draw_player_finished
    nop

    li $s0, PLAYER_ROW
    addiu $s0, $s0, -1                  # Start the held stack immediately above the player.

# The loop stops by held count. There is no separate top-row check here.
draw_player_held_loop:
    move $a0, $s0                       # $a0 = current logical row of the held stack.
    addiu $a1, $s1, 1                   # $a1 = same logical screen column as the player.
    move $a2, $s3                       # $a2 = held bubble colour.

    jal draw_unit
    nop

    addiu $s0, $s0, -1                  # Move one logical row up for the next held bubble.
    addiu $s2, $s2, -1                  # One fewer held bubble left to draw.

    bgtz $s2, draw_player_held_loop
    nop

draw_player_finished:
    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20

    jr $ra
    nop

##############################################################################
# 13 | Grab bubbles
##############################################################################
# grab_bubbles searches from the bottom of the player's column. Once it finds
# a bubble, it collects the contiguous run if its colour matches the held stack
# or the player is empty-handed.

grab_bubbles:

    addiu $sp, $sp, -8
    sw $ra, 4($sp)

    lw $t0, player_col                  # $t0 = player's zero-based board column.

    la $t1, board                       # $t1 = board base, then the cursor up the player's column.
    li $t2, PLAYFIELD_ROWS
    addiu $t2, $t2, -1                  # $t2 = board row under inspection, starting at the bottom.

    li $t3, PLAYFIELD_COLS
    mul $t4, $t2, $t3                   # $t4 = first cell index in that row.
    addu $t4, $t4, $t0                  # Add the player's column to form the cell index.
    sll $t4, $t4, 2                     # Convert the cell index to a board byte offset.
    addu $t1, $t1, $t4                  # $t1 = address of the bottom cell in the player's column.

grab_find_bottom:
    lw $t5, 0($t1)                      # $t5 = candidate bubble colour (0 means empty).

    bne $t5, $zero, grab_start
    nop

    addiu $t1, $t1, -28                 # Move up one board row (7 words x 4 bytes).
    addiu $t2, $t2, -1                  # Track the row separately to stop at the top boundary.

    bgez $t2, grab_find_bottom
    nop

    j grab_bubbles_finished             # The entire column is empty.
    nop

grab_start:
    lw $t6, held_count                  # $t6 = number of bubbles already held.

    beq $t6, $zero, grab_colour_valid   # An empty hand can take any nonempty colour.
    nop

    lw $t8, held_colour                 # $t8 = colour of the existing held stack.
    bne $t5, $t8, grab_bubbles_finished  # A nonempty hand accepts only more of the same colour.
    nop

grab_colour_valid:
    sw $t5, held_colour                 # Set the held colour ID to the colour being collected.

grab_matching_loop:
    lw $t7, 0($t1)                      # $t7 = next cell's colour while climbing the column.
    bne $t7, $t5, grab_finish           # End the grab on a gap or a different colour.
    nop

    sw $zero, 0($t1)                    # Clear the board cell just added to the held stack.

    addiu $t6, $t6, 1                   # Increase the held count, including previously held bubbles.

    addiu $t1, $t1, -28                 # Move to the cell above in the same column.
    addiu $t2, $t2, -1

    bgez $t2, grab_matching_loop
    nop

grab_finish:
    sw $t6, held_count                  # Commit the updated held count before any drawing calls.

    jal draw_board
    nop

grab_bubbles_finished:
    lw $ra, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop

##############################################################################
# 14 | Throw bubbles and trigger connected matches
##############################################################################
# throw_bubbles places the held stack below the lowest occupied cell in the target
# column. A vertical triple at the landing point seeds the recursive flood fill.
# Returns $v0 = 1 after placement, or 0 if the held stack could not be placed.

throw_bubbles:

    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)
    sw $s4, 0($sp)

    lw $s0, held_count                  # $s0 = number of bubbles to place.
    lw $s1, held_colour                 # $s1 = colour ID shared by all thrown bubbles.

    beq $s0, $zero, throw_failed
    nop

    beq $s1, $zero, throw_failed
    nop

    lw $s2, player_col                  # $s2 = target board column.

    la $s4, board                       # $s4 = board base until the placement address is formed.
    li $s3, PLAYFIELD_ROWS
    addiu $s3, $s3, -1                  # $s3 = search row, starting from the bottom.

throw_find_stack:
    bltz $s3, throw_position_found      # If the search passed row 0, the column is empty.
    nop

    li $t0, PLAYFIELD_COLS
    mul $t1, $s3, $t0                   # $t1 = index of the row's first cell.
    addu $t1, $t1, $s2                  # $t1 = index of the cell in the target column.
    sll $t1, $t1, 2                     # Convert the cell index to a byte offset.
    addu $t2, $s4, $t1                  # $t2 = candidate cell address.

    lw $t3, 0($t2)                      # $t3 = candidate colour ID.
    bne $t3, $zero, throw_position_found  # First occupied cell from the bottom anchors the throw.
    nop

    addiu $s3, $s3, -1                  # Search the same column one row higher.
    j throw_find_stack
    nop

throw_position_found:
    addiu $s3, $s3, 1                   # $s3 = first placement row (0 if the column was empty).

    addu $t0, $s3, $s0                  # $t0 = first row after the entire proposed throw.
    li $t1, PLAYFIELD_ROWS

    bgt $t0, $t1, throw_failed          # Reject the throw if the last bubble would be past row 13.
    nop

    li $t0, PLAYFIELD_COLS
    mul $t1, $s3, $t0
    addu $t1, $t1, $s2
    sll $t1, $t1, 2
    addu $s4, $s4, $t1                  # $s4 = address of the first bubble to place.

# $s4 advances by 28 bytes per bubble. On exit it points one row below
# the last placed bubble. $s3 still holds the first placed row.
throw_place_loop:
    sw $s1, 0($s4)                      # Place one bubble of the thrown colour.

    addiu $s4, $s4, 28                  # Advance the placement cursor by one board row.
    addiu $s0, $s0, -1                  # One fewer bubble left to place.

    bgtz $s0, throw_place_loop
    nop

    sw $zero, held_colour               # Clear the held colour after all placements succeed.
    sw $zero, held_count                # Clear the number of held bubbles.

    jal draw_player                     # Refresh the player overlay after emptying the held stack.
    nop

    # The final bubble is at $s4 - 28. Check the two rows above it before flooding.
    # The probe at $s4 - 84 is the higher of the two prior cells.
    addiu $t0, $s4, -84                 # $t0 = two rows above the last placed bubble.
    la    $t1, board                    # $t1 = lower address bound of the board.
    sltu  $t2, $t0, $t1                 # $t2 = 1 if the candidate address is before board.
    bne   $t2, $zero, throw_redraw      # Skip the match check before any out-of-bounds read.
    nop

    lw    $t2, 0($t0)                   # $t2 = colour two rows above the last placed bubble.
    bne   $t2, $s1, throw_redraw
    nop

    lw    $t2, 28($t0)                  # $t2 = colour one row above the last placed bubble.
    bne   $t2, $s1, throw_redraw
    nop

    move  $a0, $s3                      # $a0 = first placed row, saved throughout placement.
    move  $a1, $s2                      # $a1 = target board column.
    move  $a2, $s1                      # $a2 = thrown colour ID.
    jal   process_neighbouring_matches  # Mark the connected same-colour group.
    nop

    jal   remove_marked_bubbles         # Clear the board cells marked by the flood fill.
    nop

throw_redraw:
    jal   draw_board
    nop

    li $v0, 1                           # A placement succeeds whether or not it makes a match.
    j throw_finished
    nop

throw_failed:
    move $v0, $zero                     # $v0 = 0; held state was never modified.

throw_finished:
    lw $s4, 0($sp)
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addiu $sp, $sp, 24

    jr $ra
    nop

##############################################################################
# 15 | Keyboard polling and action dispatch
##############################################################################
# check_keyboard_inputs returns an ASCII key in $v0, or 0 if no key is ready.
# handle_key accepts the key in $a0 and dispatches to an internal action label.

check_keyboard_inputs:
    lw   $t0, ADDR_KBRD                 # $t0 = base of the keyboard registers.
    lw   $t1, 0($t0)                    # $t1 = receiver status word.
    andi $t1, $t1, 1                    # $t1 = ready bit (bit 0).

    beq  $t1, $zero, no_key
    nop

    lw   $v0, 4($t0)                    # $v0 = received character from the data register.
    jr   $ra
    nop

no_key:
    move $v0, $zero                     # $v0 = 0 tells the caller there was no key.
    jr   $ra
    nop

handle_key:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)                    # Preserve the link back to game_loop across action calls.

    beq $a0, $zero, handle_key_finished  # A zero key code has no action.
    nop

    li $t0, KEY_A
    beq $t0, $a0, handle_A_press
    nop

    li $t0, KEY_D
    beq $t0, $a0, handle_D_press
    nop

    li $t0, KEY_S
    beq $t0, $a0, handle_S_press
    nop

    li $t0, KEY_W
    beq $t0, $a0, handle_W_press
    nop

    li $t0, KEY_Q
    beq $t0, $a0, handle_Q_press
    nop

    j handle_key_finished               # Unrecognized key: take the normal return path.
    nop

handle_A_press:
    la $t0, player_state                # $t0 = base of the player state words.
    lw $t1, PLAYER_COL_OFFSET($t0)      # $t1 = current zero-based player column.

    beq $t1, 0, handle_key_finished     # Column 0 is the left movement limit.

    addi $t1, $t1, -1                   # Proposed movement: one column left.
    sw   $t1, PLAYER_COL_OFFSET($t0)    # Commit the new column to player state.

    jal count_wave_key
    nop

    j handle_key_finished
    nop

handle_D_press:
    la $t0, player_state                # $t0 = base of the player state words.
    lw $t1, PLAYER_COL_OFFSET($t0)      # $t1 = current zero-based player column.

    li $t2, PLAYFIELD_COLS
    addi $t2, $t2, -1                   # $t2 = rightmost legal board column (6).

    beq $t1, $t2, handle_key_finished   # Already at the right edge: take the return path.

    addi $t1, $t1, 1                    # Proposed movement: one column right.
    sw   $t1, PLAYER_COL_OFFSET($t0)    # Commit the new column to player state.

    jal count_wave_key
    nop

    j handle_key_finished
    nop

handle_S_press:
    jal grab_bubbles
    nop

    jal draw_player
    nop

    jal count_wave_key                  # Count the grab key even if no bubbles were collected.
    nop

    j handle_key_finished
    nop

# W attaches the held stack to the board and checks for a match.
handle_W_press:
    jal throw_bubbles
    nop

    jal count_wave_key                  # Count the throw key even if placement failed.
    nop

    j handle_key_finished
    nop

handle_Q_press:
    j game_over_exit                    # Exit directly from the quit key path.
    nop

handle_key_finished:
    lw $ra, 4($sp)                      # Reload the caller's return address.
    addi $sp, $sp, 8                    # Release this handler's frame.
    jr $ra
    nop

##############################################################################
# 16 | Main input loop
##############################################################################
# Idle iterations sleep. An input dispatches one action before repainting.

game_loop:
    jal check_keyboard_inputs           # Poll keyboard status and return the character in $v0.
    nop

    beq $v0, $zero, game_loop_continue  # Idle iteration: skip repaint and go straight to sleep.
    nop

    move $a0, $v0                       # $a0 = character passed to handle_key.
    jal handle_key
    nop

    j game_loop_draw                    # Draw the board and player after processing input.
    nop

##############################################################################
# 17 | Exit and wave control
##############################################################################
# game_over_exit is shared by the quit key and bottom-row checks.
# count_wave_key either increments the counter or processes a complete new wave.

game_over_exit:
    li $v0, 10                          # Simulator exit syscall.
    syscall

count_wave_key:
    lw $t0, moves_since_last_wave       # $t0 = actions counted since the previous wave.
    addiu $t0, $t0, 1                   # Include the current action.

    li $t1, MOVES_PER_WAVE              # $t1 = threshold for advancing a wave.
    bne $t0, $t1, save_wave_count       # Under the threshold: save the count and return.
    nop

    sw $zero, moves_since_last_wave     # On the threshold path, reset the count for the next wave.

    jal check_game_over                 # Check for game over before shifting any bubbles down.
    nop

    lw $t0, game_over                   # $t0 = game-over flag after the first check.
    bne $t0, $zero, game_over_exit
    nop

    jal advance_bubble_rows             # Shift existing rows and generate a new top row.
    nop

    jal check_game_over                 # Check whether the wave reached the bottom row.
    nop

    lw $t0, game_over                   # $t0 = game-over flag after the wave.
    bne $t0, $zero, game_over_exit
    nop

    j game_loop_draw                    # This path goes directly to repaint, bypassing the handler return.
    nop

# The below-threshold path returns using the link from the call to count_wave_key.
# The wave path above branches to the repaint label directly.
save_wave_count:
    sw $t0, moves_since_last_wave       # Commit the incremented count on the no-wave path.
    jr $ra                              # Return to the key handler on the no-wave path.

##############################################################################
# 18 | Repaint and frame pacing
##############################################################################
# The board draws first. The player overlays it because both use the last
# interior row. The sleep path also serves idle input polls.

game_loop_draw:

    jal draw_board                      # Paint board cells first, restoring the previous overlay area.
    nop

    jal draw_player                     # Paint the player and held bubbles above the board image.
    nop

    j game_loop_continue
    nop

repaint_player:
    jal draw_player
    nop

game_loop_continue:
    li $v0, 32                          # Simulator sleep syscall.
    li $a0, 16                          # $a0 = delay in milliseconds.
    syscall

    j game_loop                         # Poll the next input after sleeping.
    nop
