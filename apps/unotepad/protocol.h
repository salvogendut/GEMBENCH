/* Private application protocol, not kernel ABI. Byte offsets are explicit;
 * no host structs, pointers, page numbers or target addresses cross banks. */
#ifndef UNOTEPAD_PROTOCOL_H
#define UNOTEPAD_PROTOCOL_H
#define NP_MAX 4096u
#define NP_LINE_MAX 85u
#define NP_PACKET 512u
#define NP_DATA 32u
#define NP_CHUNK 480u
#define NP_ROW_SIZE 88u
#define NP_ROW_BATCH 5u
enum { NP_QUERY, NP_RESET, NP_KEY, NP_ALL, NP_HIT, NP_SCROLL, NP_FOLLOW,
       NP_STAGE_BEGIN, NP_STAGE_APPEND, NP_STAGE_LOAD, NP_STAGE_PASTE,
       NP_SAVED, NP_DIRTY, NP_EXPORT, NP_BAS_BEGIN, NP_BAS_READ,
       NP_VIEW_BEGIN, NP_VIEW_ROWS, NP_EDIT_BEGIN, NP_EDIT_DAMAGE, NP_TITLE,
       NP_POINT, NP_CONFIG_EXPORT };
/* VIEW_BEGIN flag: 255 = whole view, otherwise one visible row.
 * EDIT_BEGIN snapshots rendered rows into idle transactional scratch (rejected
 * while staging). EDIT_DAMAGE returns rows pairs at DATA: first/last changed
 * column (last exclusive, 255 = unchanged), auxiliary[6] = viewport scrolled.
 * Includes old/new caret cells and selection styling, not just glyph values.
 * TITLE takes an 11-byte name at DATA and returns the zero-terminated title.
 * POINT takes client-relative pixel x/y in bytes 2/3 and selection-start in
 * flag; the shared model performs the glyph/row mapping. SAVED also receives
 * the current 11-byte name at DATA and returns whether a bounded config image
 * should be published. CONFIG_EXPORT is a raw 512-byte response with no state
 * header. */
/* Input: op[0], arg0 u16[2], arg1 u16[4], flag[6], wrap[7], rows[28].
 * Output: status[1] (0 success), result u16[2], auxiliary[4..6],
 * state[8..26], payload[32..511]. Unused output bytes are zeroed.
 * State: len,cur,first,anchor,sel_a,sel_b (u16); selected,dirty (u8);
 * total rows,caret row (u16),caret column (u8).
 * Render row: length,selection-start/end (255 absent),reserved,text[84]. */
static unsigned int np_word(const unsigned char *p)
{ return p[0] | ((unsigned int)p[1] << 8); }
static void np_put(unsigned char *p,unsigned int n)
{ p[0]=(unsigned char)n;p[1]=(unsigned char)(n>>8); }
#endif
