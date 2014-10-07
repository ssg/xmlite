{
removes unused samples & unused patterns from XM modules
(c) SSG/arteffect  Jul 97

looking for comments? you're out of luck today...
}

{$I-,F-,G+,A-,S-,R-,X+,N-,E-}

uses

  Dos,Objects;

const

  tempFile : string[12] = 'XMLiTE.$$$';

  xmlVersion = '1.01';

  XMID : array[0..16] of char = 'Extended Module: ';

  XMLiTEID : array[0..19] of char = 'XMLiTE';

  xmVersion = $0104;

  xmfLinearFreqTable = 1;

  xsfNoLoop          = 0;
  xsfForwardLoop     = 1;
  xsfPingPongLoop    = 2;
  xsf16bit           = 4;

type

  TXMHeader = record
    IDText      : array[0..16] of char;
    ModuleName  : array[0..19] of char;
    EOFMarker   : char;
    TrackerName : array[0..19] of char;
    Version     : word;
    HeaderSize  : longint;
    SongLength  : word;
    RestartPos  : word;
    NumChannels : word;
    NumPatterns : word;
    NumInst     : word;
    Flags       : word;
    DefTempo    : word;
    DefBPM      : word;
    OrderTable  : array[0..255] of byte;
  end;

  TXMNote = record
    Note       : byte;
    Instrument : byte;
    Volume     : byte;
    Effect     : byte;
    Parameter  : byte;
  end;

  TXMPattern = record
    HeaderLength   : longint;
    PackType       : byte;
    Rows           : word;
    PackedSize     : word;
  end;

  TXMInstrument = record
    Size           : longint;
    Name           : array[0..21] of char;
    InstrumentType : byte;
    NumSamples     : word;
  end;

  TXMInstrumentData = record
    HeaderSize      : longint;
    SampleNumbers   : array[1..96] of byte;
    VolPoints       : array[1..48] of byte;
    PanPoints       : array[1..48] of byte;
    NumVolPoints    : byte;
    NumPanPoints    : byte;
    VolSustainPoint : byte;
    VolLoopStart    : byte;
    VolLoopEnd      : byte;
    PanSustainPoint : byte;
    PanLoopStart    : byte;
    PanLoopEnd      : byte;
    VolType         : byte;
    PanType         : byte;
    VibType         : byte;
    VibSweep        : byte;
    VibDepth        : byte;
    VibRate         : byte;
    VolFadeOut      : word;
    Reserved        : word;
  end;

  TXMSample = record
    Length     : longint;
    LoopStart  : longint;
    LoopLength : longint;
    Volume     : byte;
    Finetune   : shortint;
    Flags      : byte;
    Panning    : byte;
    RelNote    : shortint;
    Reserved   : byte;
    Name       : array[0..21] of char;
  end;

procedure Abort(s:string);
begin
  writeln(s);
  halt(1);
end;

procedure writehome(s:String);
var
  b:byte;
begin
  write(s);
  for b:=1 to length(s) do write(#8);
end;

procedure WritePerc(val,max:longint);
var
  s:String;
begin
  val := (val*100) div max;
  Str(val,s);
  writehome(s+'%');
end;

function GetStr(p:pchar; size:word):string;
var
  s:string;
begin
  byte(s[0]) := size;
  Move(p^,s[1],size);
  for size:=1 to length(s) do if s[size] < #32 then s[size] := #32;
  GetStr := s;
end;

function fix(s:string; len:byte):string;
var
  b:byte;
begin
  while length(s) < len do begin
    inc(byte(s[0]));
    s[length(s)] := #32;
  end;
  fix := s;
end;

function lower(s:string):string;
var
  b:byte;
begin
  for b:=1 to length(s) do if s[b] in ['A'..'Z'] then inc(byte(s[b]),32);
  lower := s;
end;

function ReplaceExt(s,newext:string):string;
var
  dir:dirstr;
  name:namestr;
  ext:extstr;
begin
  FSplit(s,dir,name,ext);
  ReplaceExt := dir+name+newext;
end;

procedure RenameFile(oldname,newname:string);
var
  F:File;
begin
  Assign(F,oldname);
  Rename(F,newname);
  if IOResult <> 0 then writeln('failed to rename '+oldname+' to '+newname);
end;

procedure Lighten(dir,xmfile:string);
var
  usedInstruments:array[1..128] of boolean;
  b:byte;
  I,O:TDosStream;
  h:TXMHeader;
  ph:TXMPattern;
  ih:TXMInstrument;
  id:TXMInstrumentData;
  sh:TXMSample;
  lastsize:longint;
  firstsize:longint;
  pattern:word;
  w:word;
  usedCount:word;
  Buf:PChar;
  bufsize:word;
  lastposi,lastposo:longint;
  maxused:byte;
  c:char;
  inst:byte;
  procedure finalMsg(s:string);
  begin
    writeln(s);
    I.Done;
    O.Done;
  end;
  function ioerror:boolean;
  begin
    if I.Status <> stOK then begin
      finalMsg('read error');
      ioerror := true;
    end else if O.Status <> stOK then begin
      finalMsg('write error');
      ioerror := true;
    end else ioerror := false;
  end;
begin
  FillChar(usedInstruments,SizeOf(usedInstruments),0);
  I.init(dir+xmfile,stOpenRead);
  if I.Status <> stOK then Abort('couldn''t open');
  O.Init(dir+tempFile,stCreate);
  if O.Status <> stOK then Abort('couldn''t create '+dir+tempFile);
  I.Read(h,SizeOf(h));
  if ioerror then exit;
  if h.IDText <> XMID then begin
    finalMsg('not an XM!');
    exit;
  end;
  if h.TrackerName = XMLiTEID then begin
    finalMsg('already XMLiTE''d');
    exit;
  end;
  firstsize := I.GetSize;
  if h.Version <> xmVersion then write('v',Hi(h.Version),'.',Lo(h.Version),'? ');
  if h.NumInst > 128 then begin
    finalMsg('more than 128 instruments!?');
    exit;
  end;
  Move(XMLiTEID,h.TrackerName,20);
  O.Write(h,SizeOf(h));
  for pattern:=0 to h.NumPatterns-1 do begin
    WritePerc(I.GetPos,I.GetSize);
    I.Read(ph,SizeOf(ph));
    O.Write(ph,SizeOf(ph));
    GetMem(Buf,ph.PackedSize);
    I.Read(Buf^,ph.PackedSize);
    O.Write(Buf^,ph.PackedSize);
    if ioerror then exit;
    w := 0;
    repeat
      c := Buf[w];
      inst := 0;
      if byte(c) and $80 > 0 then begin
        if byte(c) and 1 > 0 then inc(w);
        if byte(c) and 2 > 0 then begin
          inst := byte(buf[w+1]);
          inc(w);
        end;
        if byte(c) and 4 > 0 then inc(w);
        if byte(c) and 8 > 0 then inc(w);
        if byte(c) and 16 > 0 then inc(w);
        inc(w);
      end else begin
        inst := byte(buf[w+1]);
        inc(w,5);
      end;
      if inst > 128 then begin
        finalMsg('incompatible instrument data!');
        FreeMem(Buf,ph.PackedSize);
        exit;
      end;
      if inst > 0 then usedInstruments[inst] := true;
    until w>=ph.PackedSize;
    FreeMem(Buf,ph.PackedSize);
  end;
  usedCount := 0;
  for b:=1 to h.NumInst do if usedInstruments[b] then begin
    maxused := b;
    inc(usedCount);
  end;
  if usedCount > h.NumInst then begin
    finalMsg('inconsistent header!');
    exit;
  end;
  if usedCount = h.NumInst then begin
    finalMsg('no lightening possible');
    exit;
  end;
  for b:=1 to h.NumInst do begin
    lastposi := I.GetPos;
    lastposo := O.GetPos;
    WritePerc(lastposi,firstsize);
    I.Read(ih,SizeOf(ih));
    if ioerror then exit;
    if usedInstruments[b] then begin
      O.Write(ih,SizeOf(ih));
      if ioerror then exit;
      if ih.NumSamples > 0 then begin
        I.Read(id,SizeOf(id));
        O.Write(id,SizeOf(id));
        I.Seek(lastposi+ih.Size);
        O.Seek(lastposo+ih.Size);
        if ioerror then exit;
        while ih.NumSamples > 0 do begin
          I.Read(sh,SizeOf(sh));
          O.Write(sh,SizeOf(sh));
          I.Seek(I.GetPos+(id.HeaderSize-SizeOf(sh)));
          O.Seek(O.GetPos+(id.HeaderSize-SizeOf(sh)));
          while sh.Length > 0 do begin
            bufsize := 65000;
            if bufsize > sh.Length then bufsize := sh.Length;
            if bufsize > MaxAvail then bufsize := MaxAvail;
            GetMem(buf,bufsize);
            I.Read(buf^,bufsize);
            O.Write(buf^,bufsize);
            FreeMem(buf,bufSize);
            if ioerror then exit;
            WritePerc(I.GetPos,firstsize);
            dec(sh.Length,bufsize);
          end;
          dec(ih.NumSamples);
        end;
      end else begin
        I.Seek(lastposi+ih.Size);
        O.Seek(lastposo+ih.Size);
      end;
    end else begin
      w := ih.NumSamples;
      ih.NumSamples := 0;
      O.Write(ih,SizeOf(ih));
      O.Seek(lastposo+ih.Size);
      if ioerror then exit;
      if w > 0 then begin
        I.Read(id,SizeOf(id));
        I.Seek(lastposi+ih.Size);
        while w > 0 do begin
          i.Read(sh,SizeOf(sh));
          I.Seek(I.GetPos+(id.HeaderSize-SizeOf(sh)));
          I.Seek(I.GetPos+sh.Length);
          if ioerror then exit;
          dec(w);
        end;
      end else I.Seek(lastposi+ih.Size);
    end;
  end;
  I.Done;
  lastsize := O.GetSize;
  O.Done;
  if lastsize >= firstsize then writeln('no unused data') else begin
    writeln('lightened  (',lastsize,'/',firstsize,') ',((lastsize*100)/firstsize):3:1,'%');
    RenameFile(dir+xmFile,ReplaceExt(dir+xmFile,'.OLD'));
    RenameFile(dir+tempFile,dir+xmFile);
  end;
end;

var
  inf:string;
  dir:dirstr;
  name:namestr;
  ext:extstr;
  dirinfo:SearchRec;
  procedure MyExitProc;far;
  var
    F:File;
  begin
    Assign(F,dir+tempFile);
    Erase(F);
    if IOResult <> 0 then ;
  end;

begin
  writeln('XM-LiTE! v'+xmlVersion+' - (c) 1997 SSG/ARtEffECt'#13#10);
  if paramCount <> 1 then Abort('Usage: XMLiTE filespec[.XM]');
  inf := FExpand(ParamStr(1));
  if pos('.',inf) = 0 then inf := inf + '.XM';
  FSplit(inf,dir,name,ext);
  FindFirst(inf,Archive,dirinfo);
  ExitProc := @MyExitProc;
  while DosError = 0 do begin
    write(fix(lower(dirinfo.name),15));
    Lighten(dir,dirinfo.name);
    FindNext(dirinfo);
  end;
  writeln(#13#10+'SSG Operation complete');
end.