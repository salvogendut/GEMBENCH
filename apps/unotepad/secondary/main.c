/* Computation-only: editor + transactional staging. No kernel/SDK calls. */
#include "../editor.h"
#include "../protocol.h"
static np_editor_t leaf_editor;
static char staging[NP_MAX];
static unsigned int staged, total_rows, caret_row, view_index;
static unsigned char stage_active, layout_dirty=1, caret_dirty=1, last_wrap;
static unsigned char caret_col, view_rows, view_wrap;
static np_bas_t bas;
static unsigned char goal_col=255, old_col;
static unsigned int old_row,old_first;

static void layout(unsigned char width,unsigned char rows,unsigned char follow)
{
    unsigned char col;
    if (width!=last_wrap) { goal_col=255;layout_dirty=caret_dirty=1;last_wrap=width; }
    if (layout_dirty) {
        np_position(&leaf_editor,leaf_editor.len,width,&total_rows,&col);
        layout_dirty=0;
    }
    if (caret_dirty) {
        np_position(&leaf_editor,leaf_editor.cur,width,&caret_row,&caret_col);
        caret_dirty=0;
    }
    if (follow && rows) {
        if (caret_row<leaf_editor.first) leaf_editor.first=caret_row;
        else if (caret_row-leaf_editor.first>=rows) leaf_editor.first=caret_row-rows+1;
    }
}
static void snapshot(unsigned char *p)
{
    np_put(p+8,leaf_editor.len);np_put(p+10,leaf_editor.cur);
    np_put(p+12,leaf_editor.first);np_put(p+14,leaf_editor.anchor);
    np_put(p+16,leaf_editor.sel_a);np_put(p+18,leaf_editor.sel_b);
    p[20]=leaf_editor.selected;p[21]=leaf_editor.dirty;
    np_put(p+22,total_rows);np_put(p+24,caret_row);p[26]=caret_col;
}
static void render_row(unsigned char *p)
{
    unsigned char n=0,ch;
    p[1]=p[2]=255;
    while (view_index<leaf_editor.len) {
        ch=(unsigned char)leaf_editor.text[view_index];
        if (ch=='\n') { ++view_index;break; }
        if (ch>=32) {
            p[4+n]=ch;
            if (leaf_editor.selected && view_index>=leaf_editor.sel_a && view_index<leaf_editor.sel_b) {
                if (p[1]==255) p[1]=n;
                p[2]=n+1;
            }
            ++n;
        }
        ++view_index;
        if (n==view_wrap) break;
    }
    p[0]=n;
}
void secondary_main(unsigned char *p,unsigned int length)
{
    unsigned int a,b,n=0,limit;
    char title_name[11];
    unsigned char op,flag,width,rows,follow=0,bad=0,aux=0;
    if (length!=NP_PACKET) return;
    op=p[0];a=np_word(p+2);b=np_word(p+4);flag=p[6];width=p[7];rows=p[28];
    if (!width || width>=NP_LINE_MAX || !rows || rows>21) { p[1]=1;return; }
    switch (op) {
    case NP_QUERY: break;
    case NP_RESET: np_reset(&leaf_editor);stage_active=0;goal_col=255;layout_dirty=caret_dirty=1;break;
    case NP_KEY:
        if(flag>=28 && flag<=31)n=np_arrow(&leaf_editor,flag,width,&goal_col);
        else { goal_col=255;n=np_key(&leaf_editor,flag); }
        if(n)layout_dirty=caret_dirty=1;
        follow=1;break;
    case NP_ALL: goal_col=255;np_all(&leaf_editor);caret_dirty=follow=1;break;
    case NP_HIT:
        goal_col=255;
        a=np_index(&leaf_editor,a,(unsigned char)b,width);
        if (flag) leaf_editor.anchor=a;
        np_select(&leaf_editor,a);caret_dirty=follow=1;break;
    case NP_POINT:
        goal_col=255;
        aux=(unsigned char)(p[2]*2u)/3u;
        if(aux>=width)aux=width-1;
        a=leaf_editor.first+p[3]/10u;
        a=np_index(&leaf_editor,a,aux,width);
        if(flag)leaf_editor.anchor=a;
        np_select(&leaf_editor,a);caret_dirty=follow=1;break;
    case NP_SCROLL:
        layout(width,rows,0);limit=total_rows>=rows ? total_rows-rows+1 : 0;
        if (flag) leaf_editor.first=leaf_editor.first>3 ? leaf_editor.first-3 : 0;
        else leaf_editor.first+=3;
        if (leaf_editor.first>limit) leaf_editor.first=limit;
        break;
    case NP_FOLLOW: goal_col=255;follow=1;break;
    case NP_STAGE_BEGIN: staged=0;stage_active=1;break;
    case NP_STAGE_APPEND:
        if (!stage_active || a!=staged || b>NP_CHUNK || b>NP_MAX-staged) bad=1;
        else { memcpy(staging+staged,p+NP_DATA,b);staged+=b; }
        break;
    case NP_STAGE_LOAD:
        if (!stage_active) bad=1;
        else { np_loaded(&leaf_editor,staging,staged,flag);goal_col=255;layout_dirty=caret_dirty=1;stage_active=0; }
        break;
    case NP_STAGE_PASTE:
        if (!stage_active || !np_replace(&leaf_editor,staging,staged)) bad=1;
        else { goal_col=255;layout_dirty=caret_dirty=follow=1; }
        stage_active=0;break;
    case NP_SAVED: leaf_editor.dirty=0;break;
    case NP_DIRTY: leaf_editor.dirty=1;break;
    case NP_EXPORT:
        if (a>leaf_editor.len || b>NP_CHUNK) bad=1;
        else { n=leaf_editor.len-a;if(n>b)n=b; }
        break;
    case NP_BAS_BEGIN: bas.offset=0;bas.phase=0;break;
    case NP_BAS_READ: break;
    case NP_VIEW_BEGIN:
        view_index=np_index(&leaf_editor,leaf_editor.first+(flag==255 ? 0 : flag),0,width);
        view_rows=flag==255 ? rows : 1;view_wrap=width;break;
    case NP_VIEW_ROWS: break;
    case NP_EDIT_BEGIN:
        if(stage_active) { bad=1;break; }
        layout(width,rows,0);old_row=caret_row;old_col=caret_col;old_first=leaf_editor.first;
        view_index=np_index(&leaf_editor,leaf_editor.first,0,width);view_wrap=width;
        for(a=0;a<rows;++a)render_row((unsigned char *)staging+a*NP_ROW_SIZE);
        break;
    case NP_EDIT_DAMAGE: break;
    case NP_TITLE:
        memcpy(title_name,p+NP_DATA,11);break;
    default: bad=1;break;
    }
    memset(p,0,NP_PACKET);
    if (!bad) {
        if (op==NP_EXPORT) memcpy(p+NP_DATA,leaf_editor.text+a,n);
        else if (op==NP_BAS_READ) {
            n=np_bas_chunk(&leaf_editor,&bas,(char *)p+NP_DATA,NP_CHUNK);aux=bas.phase==4;
        } else if (op==NP_VIEW_ROWS) {
            while(n<NP_ROW_BATCH && view_rows) {
                render_row(p+NP_DATA+n*NP_ROW_SIZE);++n;--view_rows;
            }
        } else if(op==NP_EDIT_DAMAGE) {
            unsigned char i,j,lo,hi,len,os,ns,*old,*now=p+128;
            layout(width,rows,follow);aux=old_first!=leaf_editor.first;
            view_index=np_index(&leaf_editor,leaf_editor.first,0,width);view_wrap=width;
            for(i=0;i<rows;++i) {
                old=(unsigned char *)staging+i*NP_ROW_SIZE;render_row(now);
                lo=255;hi=0;len=old[0]>now[0] ? old[0] : now[0];
                for(j=0;j<len;++j) {
                    os=old[1]!=255 && j>=old[1] && j<old[2];
                    ns=now[1]!=255 && j>=now[1] && j<now[2];
                    if(os!=ns || (j<old[0] ? old[4+j] : ' ')!=(j<now[0] ? now[4+j] : ' ')) {
                        if(lo==255)lo=j;
                        hi=j+1;
                    }
                }
                if(old_row==old_first+i) {
                    if(old_col<lo)lo=old_col;
                    if(old_col>=hi)hi=old_col+1;
                }
                if(caret_row==leaf_editor.first+i) {
                    if(caret_col<lo)lo=caret_col;
                    if(caret_col>=hi)hi=caret_col+1;
                }
                p[NP_DATA+2*i]=lo;p[NP_DATA+2*i+1]=hi;
            }
        } else if(op==NP_TITLE) {
            unsigned char i;
            for(i=0;i<8 && title_name[i]!=' ';++i)p[NP_DATA+n++]=title_name[i];
            if(title_name[8]!=' ') {
                p[NP_DATA+n++]='.';
                for(i=8;i<11 && title_name[i]!=' ';++i)p[NP_DATA+n++]=title_name[i];
            }
            if(leaf_editor.dirty) {p[NP_DATA+n++]=' ';p[NP_DATA+n++]='*';}
        }
    }
    layout(width,rows,follow);snapshot(p);
    p[1]=bad;np_put(p+2,n);p[6]=aux;
}
