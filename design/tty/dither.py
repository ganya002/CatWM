import sys
B=[[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
G={'O':[".###.","#...#","#...#","#...#","#...#","#...#",".###."],
'U':["#...#","#...#","#...#","#...#","#...#","#...#",".###."],
'C':[".####","#....","#....","#....","#....","#....",".####"],
'H':["#...#","#...#","#...#","#####","#...#","#...#","#...#"],
'!':["#","#","#","#","#",".","#"]}
def wordmark(color,px=12,sub=3):
    word="OUCH!"; out=[]; x0=0; H=7*px
    n=px//sub
    for ch in word:
        g=G[ch]
        for r,row in enumerate(g):
            for c,v in enumerate(row):
                if v!='#': continue
                X=x0+c*px; Y=r*px
                for sy in range(n):
                    for sx in range(n):
                        yy=Y+sy*sub
                        d=1.0-max(0,(yy/H-0.35))/0.65*0.85  # density fades downward
                        gx=(X//sub+sx)%4; gy=(yy//sub)%4
                        if (B[gy][gx]+0.5)/16 < d:
                            out.append(f'<rect x="{X+sx*sub}" y="{yy}" width="{sub}" height="{sub}"/>')
        x0+=(len(g[0])+1)*px
    w=x0-px
    return f'<svg layer-name="Wordmark" width="{w}" height="{H}" viewBox="0 0 {w} {H}" xmlns="http://www.w3.org/2000/svg"><g fill="{color}">'+''.join(out)+'</g></svg>'
def band(color,w,h,sub=2,rev=False):
    out=[]
    for y in range(0,h,sub):
        for x in range(0,w,sub):
            d=x/w if not rev else 1-x/w
            if (B[(y//sub)%4][(x//sub)%4]+0.5)/16 < d: out.append(f'<rect x="{x}" y="{y}" width="{sub}" height="{sub}"/>')
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg"><g fill="{color}">'+''.join(out)+'</g></svg>'
if __name__=="__main__":
    kind=sys.argv[1]
    if kind=="word": print(wordmark(sys.argv[2]))
    else: print(band(sys.argv[2],int(sys.argv[3]),int(sys.argv[4])))
