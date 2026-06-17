; ---------------------------------------------------------------------------
; lib/fs_fat_lowram.inc - fixed low-RAM addresses for the FAT core + IDE read state,
; shared by the resident kernel and GEOBENCH.ROM (#152) when FS_STATE_LOWRAM is set.
;
; The FAT read/write core (lib/fs_fat32_core.asm) runs from the read-only ROM, so its
; writable scratch lives in low RAM that both sides agree on (FS_STATE_BASE = #1C00).
; Included by kernel/gbkern.asm (resident: navigation k_chdir/k_back use fs_dir_clus,
; and after the read code moves to the ROM the resident keeps only these addresses)
; and rom/geobench_rom.asm. fat_eoc is a read-only constant (fine in ROM).
; ---------------------------------------------------------------------------

fat_eoc         defb  #FF,#FF,#FF,#0F  ; FAT32 end-of-chain marker (const)
fs_part_lba     equ   FS_STATE_BASE+0  ; partition base LBA (0 = superfloppy)
fs_fat_lba      equ   FS_STATE_BASE+4  ; absolute FAT start LBA
fs_data_lba     equ   FS_STATE_BASE+8  ; absolute data region start LBA
fs_dir_clus     equ   FS_STATE_BASE+12 ; current directory cluster (browse dir; shared with nav)
acc             equ   FS_STATE_BASE+16 ; 32-bit work accumulator
fatsz_tmp       equ   FS_STATE_BASE+20 ; sectors per FAT (geometry calc)
fs_dir_cur_lba  equ   FS_STATE_BASE+24 ; LBA of the dir sector currently in secbuf
fn_ptr          equ   FS_STATE_BASE+28 ; fs_fat_next: cluster-var pointer
fn_within       equ   FS_STATE_BASE+30 ; fs_fat_next: FAT entry offset in sector
fs_spc          equ   FS_STATE_BASE+32 ; sectors per cluster
fs_clshift      equ   FS_STATE_BASE+33 ; log2(sectors per cluster)
fs_dir_sic      equ   FS_STATE_BASE+34 ; dir: sector within current cluster
fs_ent_idx      equ   FS_STATE_BASE+35 ; dir: entry index within current sector
fs_numfat       equ   FS_STATE_BASE+36 ; number of FAT copies
fs_is_fat16     equ   FS_STATE_BASE+37 ; #130: 1 = FAT16 volume, else FAT32
fs_root_lba     equ   FS_STATE_BASE+38 ; #130 FAT16: LBA of the fixed root directory
fs_root_secs    equ   FS_STATE_BASE+42 ; #130 FAT16: root directory size in sectors
FS_CORE_STATE_END equ FS_STATE_BASE+43 ; gbfat write state continues from here (+43..+102)
