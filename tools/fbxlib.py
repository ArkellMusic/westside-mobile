import struct, zlib
def read_prop(d,p):
    t=chr(d[p]); p+=1
    if t in 'YCFDLIB':
        fmt={'Y':'<h','C':'<B','F':'<f','D':'<d','L':'<q','I':'<i','B':'<B'}[t]; sz=struct.calcsize(fmt)
        return t,struct.unpack(fmt,d[p:p+sz])[0],p+sz
    if t in 'fdlib':
        n,enc,clen=struct.unpack('<III',d[p:p+12]); p+=12
        return t,('arr',n,enc,p,clen),p+clen
    if t in 'SR':
        n=struct.unpack('<I',d[p:p+4])[0]; p+=4
        v=d[p:p+n]; return t,(v.decode('latin1') if t=='S' else v),p+n
    raise Exception('bad prop '+t)
def read_node(d,pos,n):
    end,nprop,plen=struct.unpack('<QQQ',d[pos:pos+24]); nl=d[pos+24]
    if end==0: return None,pos+25
    name=d[pos+25:pos+25+nl].decode('latin1'); p=pos+25+nl
    props=[]
    for i in range(nprop):
        t,v,p=read_prop(d,p); props.append((t,v))
    ch=[]
    if p<end:
        while p<end-25:
            c,p2=read_node(d,p,n)
            if c is None: break
            ch.append(c); p=p2
    return {'name':name,'props':props,'children':ch,'pos':pos,'end':end},end
def top(d):
    n=len(d); pos=27; out=[]
    while pos<n-25:
        nd,pos2=read_node(d,pos,n) if True else None
        if nd is None: break
        out.append(nd); pos=pos2
        if pos>=n: break
    return out

def objects_tolerant(d):
    n=len(d); pos=27
    while pos<n-25:
        end,nprop,plen=struct.unpack('<QQQ',d[pos:pos+24]); nl=d[pos+24]; name=d[pos+25:pos+25+nl].decode('latin1')
        if name=='Objects': break
        pos=end
    ostart=pos
    end,nprop,plen=struct.unpack('<QQQ',d[pos:pos+24]); nl=d[pos+24]
    p=pos+25+nl+plen
    ch=[]; partial=None
    while p<min(end,n)-25:
        try: c,p2=read_node(d,p,n)
        except Exception as e: partial=('exc',p); break
        if c is None: break
        if c['end']>n: partial=(c['name'],p,c['end']-n); break
        ch.append(c); p=p2
    return ostart,end,ch,p,partial
def nm(c): return c['props'][1][1].split('\x00')[0]
