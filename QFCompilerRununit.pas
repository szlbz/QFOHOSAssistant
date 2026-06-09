unit QFCompilerRununit;

{$MODE Delphi}

interface

uses
  LCLIntf, LCLType, LMessages, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, IniFiles,
  DefaultTranslator,
  //GetCompilerOptions:
  CompilerOptions, LazUTF8,LazFileUtils,Process,LConvEncoding,

  //IDE 调试助手需要用到的单元
  DefineTemplates, CompOptsIntf, TransferMacros,
  LCLProc, BaseIDEIntf, ProjectIntf, LazConfigStorage,
  ComCtrls,
  FileUtil,
  IdeDebuggerOpts,
  IDECommands, IDEWindowIntf, LazIDEIntf, MenuIntf, SynEdit
  , Types;

type

  { TQFCompilerRun }

  TQFCompilerRun = class(TForm)
    btnRemoteDebug: TButton;
    Button1: TButton;
    Button2: TButton;
    CBCPU: TComboBox;
    CBOS: TComboBox;
    CBSUBCPUOS: TComboBox;
    ComboBox1: TComboBox;
    Edit1: TEdit;
    HarmonyProjectPath: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    DevEcoPath: TLabeledEdit;
    Label6: TLabel;
    Memo1: TSynEdit;
    PageControl1: TPageControl;
    pInfo: TPanel;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure SaveProjectConfig;
    procedure CBCPUChange(Sender: TObject);
    procedure CBSUBCPUOSChange(Sender: TObject);
    procedure Edit1MouseEnter(Sender: TObject);
    procedure eServerAddrExit(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure btnRemoteDebugClick(Sender: TObject);
    procedure SetProjectConfig;
    procedure SetProjectDebugConfig;
    procedure GetCrossLibList;
    procedure ModifyFpccfg;
    function GetlibVer:String;
    function GetCompilerOpts:String;
    procedure RunHvigor;
  private
    { Private declarations }
    FOHOSSDKConfigDir:String;
    LibFileList:TStringList;
    Nextno:Int64;
    TargetCPUOS:String;
    eRequestFileName:String;
    eLocalFileName:String;
    eGDBFileName:String;
    crosspath:String;
    IsDownLibFile:Boolean;
    ProjectLocalFileName:String;
  public
    { Public declarations }
  end;

var
  QFCompilerRun: TQFCompilerRun;
  QFCompilerRunCreator: TIDEWindowCreator;

resourcestring
  OSSuboptions = 'OS Sub options';
  formcaption = 'QFOHOSCompilerRun Assistant';
  MenuItemCaption = 'QFOHOSCompilerRun Assistant';
  BuildMode = 'Build Mode';
  FbtnRemoteDebug = 'Compiler / Run';
  FbtnRemoteDebughint = 'Compile and run the current project';//'编译当前project及运行当前project';
  FFastCompilerBtn = 'Fast Compiler';
  FCompilerSpecificversionBtn ='Compile a specific version of libc';
  FCompilerSpecificversionBtnhint = 'Compile a specific version of libc, such as compiling a lower version of a program from a higher version.';//'编译特定版本的libc，如：在高版本编译低版本的程序。';
  TargetFileName = 'TargetFileName';


procedure ShowQFCompilerRun(Sender: TObject);
procedure Register;

implementation

{$R *.lfm}

//dock windows用
procedure CreateTQFCompilerRun(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if CompareText(aFormName, 'QFCompilerRun')<>0 then
  begin
    DebugLn(['ERROR: CreateTQFCompilerRun: there is already a form with '
      +'this name']);
    exit;
  end;
  IDEWindowCreators.CreateForm(AForm, TQFCompilerRun,
    DoDisableAutoSizing,
    LazarusIDE.OwningComponent);
  AForm.Name:=aFormName;
  QFCompilerRun:=AForm as TQFCompilerRun;
end;

procedure ShowQFCompilerRun(Sender: TObject);
begin
  QFCompilerRun:=TQFCompilerRun.Create(nil);
  QFCompilerRun.ShowModal;
  QFCompilerRun.Free;
end;

procedure Register;
var
  CmdCatToolMenu: TIDECommandCategory;
  ToolQFCompilerRunCommand: TIDECommand;
  //MenuItemCaption: String;
  MenuCommand: TIDEMenuCommand;
begin
  // register shortcut and menu item
  //MenuItemCaption:='QFCompilerRun';//'远程调试助手'; // <- this caption should be replaced by a resourcestring
  // search shortcut category
  CmdCatToolMenu:=IDECommandList.FindCategoryByName(CommandCategoryCustomName);//CommandCategoryToolMenuName);
  // register shortcut
  ToolQFCompilerRunCommand:=RegisterIDECommand(CmdCatToolMenu,
    'QFOHOSCompilerRun',
    MenuItemCaption,
    IDEShortCut(VK_F6, []), // <- set here your default shortcut
    CleanIDEShortCut, nil, @ShowQFCompilerRun);

  // register menu item in Project menu
  MenuCommand:=RegisterIDEMenuCommand(itmRunBuilding,//mnuRun, //新注册菜单的位置
    'QFOHOSCompilerRun', //菜单名--唯一标识（不能有中文）
    MenuItemCaption,//菜单标题
    nil, nil,ToolQFCompilerRunCommand);

end;

function SetDirSeparatorsEx( FileName : String):String;
Var I : longint;

begin
  Result:=FileName;
  For I:=1 to Length(FileName) do
  begin
    if (FileName[I]='/') or (FileName[I]='\') then
      FileName[i]:=DirectorySeparator;
  end;
  Result:=FileName;
end;

function TQFCompilerRun.GetLibVer:String;
var
  f:TStringList;
  p,s,str:String;
  i:Integer;
begin
  Result:='';
  p:=LazarusIDE.GetPrimaryConfigPath;
  p:=p.Replace('config_lazarus','',[]);
  p:=SetDirSeparatorsEx(p+'fpc\bin\'+lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%})+'\fpc.cfg');
  try
    f:=TStringList.Create;
    f.LoadFromFile(p);
    for i:=0 to f.Count-1 do
    begin
      str:=SetDirSeparatorsEx('\cross\lib\'+CBCPU.Text+'-'+CBOS.Text);
      if pos(str,SetDirSeparatorsEx(f[i]))>0 then
      begin
        Result:=Copy(f[i],pos(CBCPU.Text+'-'+CBOS.Text,f[i]),Length(f[i]));
        Break;
      end;
    end;
  finally
    f.Free;
  end;
end;


procedure TQFCompilerRun.ModifyFpccfg;
var
  f:TStringList;
  p,s:String;
  i:Integer;
begin
  p:=LazarusIDE.GetPrimaryConfigPath;
  p:=p.Replace('config_lazarus','',[]);
  p:=SetDirSeparatorsEx(p+'fpc\bin\'+lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%})+'\fpc.cfg');
  try
    f:=TStringList.Create;
    f.LoadFromFile(p);
    for i:=0 to f.Count-1 do
    begin
      if pos(SetDirSeparatorsEx('\cross\lib\'+CBCPU.Text+'-'+CBOS.Text), f[i])>0 then
      begin
        s:=Copy(f[i],1,pos(CBCPU.Text+'-'+CBOS.Text,f[i])-1);
        f[i]:=s+CBSUBCPUOS.Text;
      end;
      if CBSUBCPUOS.Text='loongarch64-linux' then
      begin
        if LowerCase(Copy(f[i],1,12))=LowerCase('-FL/lib64/ld') then
          f[i]:= '-FL/lib64/ld.so.1';//abi1.0;
      end;
      if CBSUBCPUOS.text='loongarch64-linux_abi2.0' then
      begin
        if LowerCase(Copy(f[i],1,12))=LowerCase('-FL/lib64/ld') then
          f[i]:= '-FL/lib64/ld-linux-loongarch-lp64d.so.1' ; //abi2.0
      end;
    end;
    f.SaveToFile(p);
  finally
    f.Free;
  end;
end;

procedure TQFCompilerRun.GetCrossLibList;
var
  LibDirList:TStringList;
  i:Integer;
  libdir,s:String;
  Config: TConfigStorage;
  GenerateDebugInfo,crossdir:String;
begin
  try
    Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
    if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
    begin
      GenerateDebugInfo:=Config.GetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','');
      if LowerCase(GenerateDebugInfo)='true' then
         combobox1.ItemIndex:=0
      else
         combobox1.ItemIndex:=1;
    end;
  finally
     Config.Free;
  end;

  crossdir:=LazarusIDE.GetPrimaryConfigPath;
  crossdir:=crossdir.Replace('config_lazarus','',[]);
  crossdir:=crossdir+'cross/lib/';
  crossdir:=SetDirSeparatorsEx(crossdir);
  crosspath:=crossdir;
  try
    CBSUBCPUOS.Items.Clear;
    LibDirList:=TStringList.Create;

    LibDirList:=FindAllDirectories(crossdir, False);
    libdir:=CBCPU.Text+'-'+CBOS.Text;
    for i := 0 to LibDirList.Count - 1 do
    begin
      if pos(libdir, LibDirList[i])>0 then
      begin
        s:=Copy(LibDirList[i],pos(libdir,LibDirList[i]),Length(LibDirList[i]));
        CBSUBCPUOS.Items.Add(s);
      end;
    end;
    CBSUBCPUOS.ItemIndex:=CBSUBCPUOS.Items.IndexOf(GetlibVer);
  finally
     LibDirList.Free;
  end;
end;

procedure TQFCompilerRun.SaveProjectConfig;
var
  Config: TConfigStorage;
  TargetFile:String;
  TargetCPU:String;
  TargetOS:String;
  guid: TGUID;
begin
  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    TargetCPU:=CBCPU.Items[CBCPU.ItemIndex];
    TargetOS:=CBOS.Items[CBOS.ItemIndex];;

    CBSUBCPUOSChange(self);

    LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU:=TargetCPU;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS:=TargetOS;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetFilename:=Edit1.Text;

    TargetCPUOS:=TargetCPU+'-'+TargetOS;

    eGDBFileName := StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','fpcbootstrap',[]);

    if SetDirSeparatorsEx(eGDBFileName[Length(eGDBFileName)])<>SetDirSeparatorsEx('/') then
      eGDBFileName:=eGDBFileName+SetDirSeparatorsEx('/');
    eGDBFileName:=SetDirSeparatorsEx(eGDBFileName+GetCompiledTargetCPU+'-'+GetCompiledTargetOS+
      '/gdb/'+TargetCPUOS+'/gdb'{$ifdef windows}+'.exe'{$endif});

    Config.DeletePath('ProjectOptions/Debugger');
    Config.SetValue('CompilerOptions/CodeGeneration/TargetCPU/Value',TargetCPU);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetOS/Value',TargetOS);
    Config.SetValue('CompilerOptions/Target/Filename/Value',Edit1.Text);
    LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
    Config.Free;
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
end;

procedure TQFCompilerRun.Button2Click(Sender: TObject);
var
   myini:TIniFile;
begin
  if SelectDirectoryDialog1.Execute then
    HarmonyProjectPath.Text:=IncludeTrailingPathDelimiter(SelectDirectoryDialog1.FileName);

  if DirectoryExists(HarmonyProjectPath.Text+'entry') then
  begin
    myini:=TIniFile.Create(FOHOSSDKConfigDir+'ohos_sdk_path.cfg');
    myini.WriteString('参数','sdk目录',DevEcoPath.Text);
    myini.WriteString('参数','HarmonyOS 项目目录',HarmonyProjectPath.Text);
    myini.Free;
  end
  else
  begin
    HarmonyProjectPath.Text:='';
    ShowMessage('选择鸿蒙项目的根目录不正确，请重新选择！');
  end;

end;

procedure TQFCompilerRun.Button1Click(Sender: TObject);
var
   myini:TIniFile;
begin
  if SelectDirectoryDialog1.Execute then
    DevEcoPath.Text:=IncludeTrailingPathDelimiter(SelectDirectoryDialog1.FileName);
  if fileExists(DevEcoPath.Text+'bin\devecostudio64.exe') then
  begin
    myini:=TIniFile.Create(FOHOSSDKConfigDir+'ohos_sdk_path.cfg');
    myini.WriteString('参数','sdk目录',DevEcoPath.Text);
    myini.WriteString('参数','HarmonyOS 项目目录',HarmonyProjectPath.Text);
    myini.Free;
  end
  ELSE
  begin
   DevEcoPath.Text:='C:\Program Files\Huawei\DevEco Studio';
   ShowMessage(ExtractFileName('选择的目录不正确，请重新选择。'));
  end;

end;

function TQFCompilerRun.GetCompilerOpts:String;
var
  Flags: TCompilerCmdLineOptions;
  CompOptions: TStringListUTF8Fast;
  CompilerOpts: TBaseCompilerOptions;
begin
  CompilerOpts:=TLazProject(LazarusIDE.ActiveProject).LazCompilerOptions as TBaseCompilerOptions ;
  CompilerOpts.TargetCPU:=CBCPU.Text;
  CompilerOpts.TargetOS:=CBOS.Text;
  Result:='';
  //if CompilerOpts=nil then exit;

  // set flags
  Flags:=CompilerOpts.DefaultMakeOptionsFlags;
  Include(Flags,ccloAddCompilerPath);//添加编译器路径
  Include(Flags,ccloAbsolutePaths); //使用绝对路径

  // get command line parameters (include compiler path)
  CompOptions := CompilerOpts.MakeCompilerParams(Flags);
  try
    CompOptions.Add(CompilerOpts.GetDefaultMainSourceFileName);
    Result:=MergeCmdLineParams(CompOptions);
  finally
    CompOptions.Free;
  end;
end;

procedure TQFCompilerRun.CBCPUChange(Sender: TObject);
begin
  GetCrossLibList;
  CBSUBCPUOSChange(Self);
end;

procedure TQFCompilerRun.CBSUBCPUOSChange(Sender: TObject);
var
  TargetFile:String;
  tmp:String;
begin
  TargetFile:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetFilename;
  if (CBOS.Text<>'ohos') and (pos('$(TargetCPU)',TargetFile)>0) then
    TargetFile:=copy(TargetFile,1,pos('$(TargetCPU)',TargetFile)-2);

  tmp:=CBSUBCPUOS.Text;
  tmp:=tmp.Replace(CBCPU.Text+'-'+CBOS.Text,'',[]);
  tmp:='$(TargetCPU)-$(TargetOS)'+tmp;
  if CBOS.Text<>'ohos' then
  begin
    if CBSUBCPUOS.Text<>'' then
      Edit1.Text:=TargetFile +'_'+tmp
    else
      Edit1.Text:=TargetFile;
  end
  else
  begin
    tmp:=Edit1.Text;
    //Edit1.Text:=tmp.Replace('_$(TargetCPU)-$(TargetOS)','',[]);
  end;
  if (CBSUBCPUOS.Text)='' then
  begin
    if cbcpu.Text='ohos' then
    Edit1.Text:=TargetFile
    else
    Edit1.Text:=TargetFile;// +'_$(TargetCPU)-$(TargetOS)';
  end;
end;

procedure TQFCompilerRun.Edit1MouseEnter(Sender: TObject);
begin
  Edit1.Hint:=Edit1.Text;
end;

procedure TQFCompilerRun.eServerAddrExit(Sender: TObject);
begin
  SetProjectConfig;
end;

procedure TQFCompilerRun.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsDownLibFile then
  begin
    IsDownLibFile:=False;
    CanClose:=False;
  end;
end;

procedure TQFCompilerRun.SetProjectConfig;
var
  Config: TConfigStorage;
  TargetFile:String;
  TargetCPU:String;
  TargetOS:String;
  guid: TGUID;
  guidStr: string;
  tmp:String;
begin
  LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    TargetCPU:=Config.GetValue('CompilerOptions/CodeGeneration/TargetCPU/Value','');
    TargetOS:=Config.GetValue('CompilerOptions/CodeGeneration/TargetOS/Value','');
    if TargetCPU='' then
      TargetCPU:=lowerCase({$I %FPCTARGETCPU%});
    if TargetOS='' then
      TargetOS:=lowerCase({$I %FPCTARGETOS%});
    TargetCPUOS:=TargetCPU+'-'+TargetOS;
    if trim(TargetCPUOS)='-' then
      TargetCPUOS:=lowerCase({$I %FPCTARGETCPU%})+'-'+lowerCase({$I %FPCTARGETOS%});

    LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU:=TargetCPU;
    LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS:=TargetOS;

    TargetFile:=Config.GetValue('CompilerOptions/Target/Filename/Value','');
    TargetFile:=TargetFile.Replace('$(TargetCPU)',TargetCPU,[]);
    TargetFile:=TargetFile.Replace('$(TargetOS)',TargetOS,[]);

    eGDBFileName:=StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','fpcbootstrap',[]);
    if SetDirSeparatorsEx(eGDBFileName[Length(eGDBFileName)])<>SetDirSeparatorsEx('/') then
      eGDBFileName:=eGDBFileName+SetDirSeparatorsEx('/');
    eGDBFileName:=SetDirSeparatorsEx(eGDBFileName+GetCompiledTargetCPU+'-'+GetCompiledTargetOS+
      '/gdb/'+TargetCPUOS+'/gdb'{$ifdef windows}+'.exe'{$endif});

    eLocalFileName:=ExtractFilePath(LazarusIDE.ActiveProject.ProjectInfoFile)+TargetFile;
    ShowMessage('eLocalFileName:'+eLocalFileName);
    ShowMessage('TargetFile:'+TargetFile);
    eRequestFileName:=TargetFile;
    Config.DeletePath('ProjectOptions/Debugger');
    Config.SetValue('CompilerOptions/CodeGeneration/TargetCPU/Value',TargetCPU);
    Config.SetValue('CompilerOptions/CodeGeneration/TargetOS/Value',TargetOS);
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
  LazarusIDE.DoSaveAll([sfProjectSaving]);  //保存
  Config.Free;

  TargetFile:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetFilename;
  if pos('$(TargetCPU)',TargetFile)>0 then
    TargetFile:=copy(TargetFile,1,pos('$(TargetCPU)',TargetFile)-2);

  tmp:=CBSUBCPUOS.Text;
  tmp:=tmp.Replace(CBCPU.Text+'-'+CBOS.Text,'',[]);
  tmp:='$(TargetCPU)-$(TargetOS)'+tmp;
  if cbos.Text<>'ohos' then
  begin
    if CBSUBCPUOS.Text<>'' then
      Edit1.Text:=TargetFile +'_'+tmp
    else
      Edit1.Text:=TargetFile;
  end
  else
  begin
    tmp:=Edit1.Text;
    //Edit1.Text:=tmp.Replace('_$(TargetCPU)-$(TargetOS)','',[]);
  end;

end;

procedure TQFCompilerRun.SetProjectDebugConfig;
var
  Config: TConfigStorage;
  TargetFile:String;
  GenerateDebugInfo:String;
begin
  Config:=GetIDEConfigStorage(LazarusIDE.ActiveProject.ProjectInfoFile,true);
  if Config.GetValue('ProjectOptions/Version/Value','')<>'' then
  begin
    TargetFile:=Config.GetValue('CompilerOptions/Target/Filename/Value','');

    ProjectLocalFileName:=ExtractFilePath(LazarusIDE.ActiveProject.ProjectInfoFile)+TargetFile;
    ProjectLocalFileName:=ProjectLocalFileName.Replace('$(TargetCPU)',CBCPU.Text,[]);
    ProjectLocalFileName:=ProjectLocalFileName.Replace('$(TargetOS)',CBOS.Text,[]);

    GenerateDebugInfo:=Config.GetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','');
    if ComboBox1.ItemIndex=1 then
      Config.SetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','False')
    else
      Config.SetValue('CompilerOptions/Linking/Debugging/GenerateDebugInfo/Value','True');
  end
  else
  begin
    ShowMessage('新建project，先保存project再使用。');
    btnRemoteDebug.Enabled:=False;
  end;
  Config.Free;
end;

procedure TQFCompilerRun.FormCreate(Sender: TObject);
var
  crossdir:String;
  myini:TIniFile;
begin
  FOHOSSDKConfigDir := LazarusIDE.GetPrimaryConfigPath + PathDelim + 'OHOSSDKConfig' + PathDelim;
  ForceDirectories(FOHOSSDKConfigDir);

  myini:=TIniFile.Create(FOHOSSDKConfigDir+'ohos_sdk_path.cfg');
  DevEcoPath.Text:= myini.ReadString('参数','sdk目录','');
  HarmonyProjectPath.Text:= myini.ReadString('参数','HarmonyOS 项目目录','');
  myini.Free;

  Self.Caption:=formcaption;
  Label3.Caption:=OSSuboptions;
  Label4.Caption:=TargetFileName;
  Label5.Caption:=BuildMode;
  btnRemoteDebug.Caption:=FbtnRemoteDebug;
  btnRemoteDebug.Hint:=FbtnRemoteDebughint;

  //SetProjectConfig;
  CBCPU.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetCPU;
  CBOS.Text:=LazarusIDE.ActiveProject.LazCompilerOptions.TargetOS;
  if CBCPU.Text='' then
    CBCPU.Text:=lowerCase({$I %FPCTARGETCPU%});
  if CBOS.Text='' then
    CBOS.Text:=lowerCase({$I %FPCTARGETOS%});
  if CBOS.ItemIndex<0 then CBOS.ItemIndex:=0;
  GetCrossLibList;
  CBSUBCPUOSChange(Self);
  crossdir:=StringReplace(LazarusIDE.GetPrimaryConfigPath,'config_lazarus','',[]);
  crossdir:=SetDirSeparatorsEx(crossdir+'cross/lib/');
  {$ifdef linux}
  if not DirectoryExists(crossdir) then
    CompilerSpecificversionBtn.Enabled:=false
  else
    CompilerSpecificversionBtn.Enabled:=true;
  {$endif}
end;

procedure TQFCompilerRun.btnRemoteDebugClick(Sender: TObject);
begin
  SaveProjectConfig;
  ModifyFpccfg;
  SetProjectDebugConfig;
  LazarusIDE.DoOpenProjectFile(LazarusIDE.ActiveProject.ProjectInfoFile,[ofRevert]); //重新打开project
  btnRemoteDebug.Enabled:=False;
  //编译当前project
  if LazarusIDE.DoBuildProject(crBuild,[]) = mrOK then
  begin
    if CBOS.Text='ohos' then
    begin
       RunHvigor;
    end
    else
    if ((lowerCase(CBCPU.Text)=lowerCase({$I %FPCTARGETCPU%})) and
      (lowerCase(CBOS.Text)=lowerCase({$I %FPCTARGETOS%}))) or
      (lowerCase(copy(CBOS.Text,1,3))='win') and (copy(lowerCase({$I %FPCTARGETOS%}),1,3)='win') then
    begin
      LazarusIDE.DoRunProject;
      Close;
    end;
  end
  else
    Close;
  btnRemoteDebug.Enabled:=True;
end;

procedure TQFCompilerRun.RunHvigor;
var
  AProcess: TProcess;
  CmdLine: string;
  Buffer: array[0..4095] of AnsiChar; // 用于读取输出的缓冲区
  BytesRead: LongInt;
  LineBuffer: string;     // 新增：用于拼接不完整行的缓冲区
  OutputLine: string;     // 新增：提取出的完整行
  PosLF: Integer;         // 新增：换行符位置
  cpu:String;

  function StripAnsiManual(const Input: string): string;
  var
    i: Integer;
    InEscape: Boolean;
  begin
    Result := '';
    InEscape := False;
    i := 1;
    while i <= Length(Input) do
    begin
      if (Input[i] = #27) then // #27 就是 ESC 字符
      begin
        InEscape := True;
        Inc(i);
        Continue;
      end;

      if InEscape then
      begin
        // 转义序列的结束字母通常在 A-Z 或 a-z 之间 (比如 m, H, J)
        // 也可能是 @ 等
        if (Input[i] >= 'A') and (Input[i] <= 'Z') or
           (Input[i] >= 'a') and (Input[i] <= 'z') then
          InEscape := False;
        Inc(i);
        Continue;
      end;

      // 不是转义码的部分，保留下来
      Result := Result + Input[i];
      Inc(i);
    end;
  end;

  function getAbility: String;
  var
    slist: TStringList;
    i, p: Integer;
    line, tempStr: string;
    isInAbilities: Boolean;
  begin
    Result := '';
    if FileExists(HarmonyProjectPath.Text + 'entry\src\main\module.json5') then
    begin
      slist := TStringList.Create;
      try
        slist.LoadFromFile(HarmonyProjectPath.Text + 'entry\src\main\module.json5');

        isInAbilities := False;

        // 索引从 0 开始
        for i := 0 to slist.Count - 1 do
        begin
          line := Trim(slist[i]); // 去除行首尾空格，方便判断

          // 检测是否进入了 abilities 节点
          if Pos('"abilities"', line) > 0 then
            isInAbilities := True;

          // 如果在 abilities 节点内，且遇到了右中括号，说明 abilities 遍历结束了，可以退出
          if isInAbilities and (Pos(']', line) > 0) then
            Break;

          // 在 abilities 内部查找 name
          if isInAbilities then
          begin
            // 寻找格式如 "name": "xxx" 或 "name":"xxx"
            if (Pos('"name"', line) > 0) and (Pos(': "', line) > 0) then
            begin
              // 找到冒号和引号的位置，截取引号后面的内容
              p := Pos(': "', line);
              tempStr := Copy(line, p + 3, MaxInt); // 截取到行尾，例如: EntryAbility",

              // 去除尾部的双引号和逗号
              p := Pos('"', tempStr);
              if p > 0 then
                tempStr := Copy(tempStr, 1, p - 1);

              Result := Trim(tempStr); // 得到干净的 EntryAbility
              Break; // 找到第一个即退出循环
            end;
          end;
        end;

      finally
        slist.Free;
      end;
    end;
  end;

  function getbundleName:String;
  var
    slist:TStringList;
    j,i:Integer;
    s1,tmp:String;
  begin
    Result:='';
    if FileExists(HarmonyProjectPath.text+'entry\build\default\outputs\default\pack.info') then
    begin
      slist:=TStringList.Create;
      try
        slist.LoadFromFile(HarmonyProjectPath.text+'entry\build\default\outputs\default\pack.info');
        tmp:=slist.Text;
        i:=pos('"bundleName":"',tmp);
        s1:='';
        for j:=i+14 to Length(tmp) do
        begin
          if (tmp[j]='"') and (tmp[j+1]=',') then
          begin
             Result:=s1;
             Break;
          end
          else
            s1:=s1+tmp[j];

        end;
      finally
        slist.Free;
      end;
    end;
  end;

begin
  HarmonyProjectPath.Text:=IncludeTrailingPathDelimiter(HarmonyProjectPath.Text);
  DevEcoPath.text:=IncludeTrailingPathDelimiter(DevEcoPath.text);
  cpu:='';
  if cbcpu.Text='aarch64' then cpu:='arm64-v8a';
  if cbcpu.Text='x86_64' then cpu:='x86_64';
  if cbcpu.Text='loongarch64' then cpu:='loongarch64';
  if cpu='' then Exit;

  ProjectLocalFileName:=ProjectLocalFileName;
  if not DirectoryExists(HarmonyProjectPath.Text+'entry\libs\'+cpu) then
    ForceDirectories(HarmonyProjectPath.Text+'entry\libs\'+cpu);
  if FileExists(ProjectLocalFileName) then
  begin
    if pos('.so',ProjectLocalFileName)>0 then
    CopyFile(ProjectLocalFileName,
    HarmonyProjectPath.Text+'entry\libs\'+cpu+'\'+ ExtractFileName(ProjectLocalFileName))
    else
    CopyFile(ProjectLocalFileName,
    HarmonyProjectPath.Text+'entry\libs\'+cpu+'\'+ ExtractFileName(ProjectLocalFileName)+'.so');
  end;

  AProcess := TProcess.Create(nil);
  try
    AProcess.CurrentDirectory := HarmonyProjectPath.text;
    AProcess.Executable := 'cmd.exe';

    // 将所有命令拼接成一个字符串，作为 /c 的唯一参数
    // 注意使用双引号正确包裹包含空格的路径
    CmdLine := 'set NODE_DEBUG=child_process'
             + ' & set "DEVECO_SDK_HOME='+DevEcoPath.text + 'sdk"'
             + ' & set "JAVA_HOME=' + DevEcoPath.text + 'jbr"'
             + ' & set "PATH='+ DevEcoPath.text + 'jbr\bin;%PATH%' + DevEcoPath.text + 'tools\hvigor\bin;'
             + DevEcoPath.text + 'sdk\default\openharmony\toolchains;'
             + DevEcoPath.text + 'tools\node"'
             + ' & hvigorw assembleHap';

    AProcess.Parameters.Add('/c');
    AProcess.Parameters.Add(CmdLine);

    AProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    AProcess.Execute;

    LineBuffer := ''; // 初始化行缓冲区为空

    // 循环读取输出
    while AProcess.Running or (AProcess.Output.NumBytesAvailable > 0) do
    begin
      if AProcess.Output.NumBytesAvailable > 0 then
      begin
        BytesRead := AProcess.Output.Read(Buffer, SizeOf(Buffer) - 1);
        if BytesRead > 0 then
        begin
          Buffer[BytesRead] := #0; // 添加字符串结束符
          // 将读取到的内容追加到行缓冲区后面
          LineBuffer := LineBuffer + string(Buffer);

          // 查找换行符 #10 (即 LF，Linux/Windows通用换行标识)
          PosLF := Pos(#10, LineBuffer);

          // 只要缓冲区中存在换行符，就不断提取完整的行
          while PosLF > 0 do
          begin
            // 提取换行符之前的字符串作为一行
            OutputLine := Copy(LineBuffer, 1, PosLF - 1);

            // 移除可能存在的回车符 #13 (即 CR，处理 Windows 的 \r\n 换行)
            if (Length(OutputLine) > 0) and (OutputLine[Length(OutputLine)] = #13) then
              SetLength(OutputLine, Length(OutputLine) - 1);

            // 在这里处理完整的行！
            if OutputLine <> '' then
            begin
              Memo1.Lines.Add(StripAnsiManual(OutputLine));
              Memo1.TopLine :=  MaxInt;
            end;

            // 从缓冲区中删除已经处理过的这行和换行符
            Delete(LineBuffer, 1, PosLF);

            // 继续查找下一个换行符
            PosLF := Pos(#10, LineBuffer);
          end;
        end;
      end
      else
      begin
        Sleep(50);
      end;

      Application.ProcessMessages; // 保持界面响应
    end;

    // === 重要：循环结束后，缓冲区可能还剩下最后一行（没有以换行符结尾） ===
    if LineBuffer <> '' then
    begin
      // 同样处理可能存在的 #13
      if (Length(LineBuffer) > 0) and (LineBuffer[Length(LineBuffer)] = #13) then
        SetLength(LineBuffer, Length(LineBuffer) - 1);

      if LineBuffer <> '' then
      begin
        Memo1.Lines.Add(StripAnsiManual(LineBuffer));
        Memo1.TopLine :=  MaxInt;
      end;
    end;

    AProcess.CurrentDirectory := HarmonyProjectPath.text;
    AProcess.Executable := 'cmd.exe';

    // 将所有命令拼接成一个字符串，作为 /c 的唯一参数
    // 注意使用双引号正确包裹包含空格的路径
    CmdLine :=
               ' & set "DEVECO_SDK_HOME='+DevEcoPath.text + 'sdk"'
             + ' & set "JAVA_HOME=' + DevEcoPath.text + 'jbr"'
             + ' & set "PATH='+ DevEcoPath.text + 'jbr\bin;' + DevEcoPath.text + 'tools\hvigor\bin;'
             + DevEcoPath.text + 'sdk\default\openharmony\toolchains;'
             + DevEcoPath.text + 'tools\node"'
             + ' & hdc install "'+HarmonyProjectPath.text+'entry\build\default\outputs\default\entry-default-unsigned.hap"'
             + ' & hdc shell aa start -a '+getAbility+' -b '+getbundleName;

    AProcess.Parameters.Add('/c');
    AProcess.Parameters.Add(CmdLine);

    AProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    AProcess.Execute;

  finally
    AProcess.Free;
  end;
end;

end.
