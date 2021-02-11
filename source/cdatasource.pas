unit cDataSource;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ComCtrls,
  cGlobal;

type
  TCaseCount = Int64;
  TCaseArray = array of TCaseCount;

  TcDataItem = class
  private
    FID: Integer;
    FName: String;
    FParentName: String;
    FLongitude: Double;
    FLatitude: Double;
    FPopulation: Int64;
    FFirstDate: TDate;
    FConfirmed: TCaseArray;
    FDeaths: TCaseArray;
    FRecovered: TCaseArray;

    function GetCount(ACaseType: TPrimaryCaseType): Integer;

    function GetCumulativeConfirmed(AIndex: Integer): TCaseCount;
    function GetCumulativeDeaths(AIndex: Integer): TCaseCount;
    function GetCumulativeRecovered(AIndex: Integer): TCaseCount;
    function GetCumulativeSick(AIndex: Integer): TCaseCount;

    function GetDate(AIndex: Integer): TDate;

    function GetNewConfirmed(AIndex: Integer): TCaseCount;
    function GetNewDeaths(AIndex: Integer): TCaseCount;
    function GetNewRecovered(AIndex: Integer): TCaseCount;
    function GetNewSick(AIndex: Integer): TCaseCount;

    function GetNormalizedNewConfirmed(AIndex: Integer): Double;
    function GetNormalizedNewDeaths(AIndex: Integer): Double;
    function GetNormalizedNewRecovered(AIndex: Integer): Double;

  public
    function GetFirstDate: TDate;
    function GetLastDate: TDate;
    function HasData(ACaseType: TPrimaryCaseType): Boolean;

    procedure SetCases(AFirstDate: TDate; const ACases: TCaseArray;
      ACaseType: TPrimaryCaseType);

    property ID: Integer read FID write FID;
    property Name: String read FName write FName;
    property ParentName: String read FParentName write FParentName;
    property Longitude: Double read FLongitude write FLongitude;
    property Latitude: Double read FLatitude write FLatitude;
    property Population: Int64 read FPopulation write FPopulation;

    property FirstDate: TDate read FFirstDate;
    property Date[AIndex: Integer]: TDate read GetDate;

    property Count[ACaseType: TPrimaryCaseType]: Integer read GetCount;

    property CumulativeConfirmed[AIndex: Integer]: TCaseCount read GetCumulativeConfirmed;
    property CumulativeDeaths[AIndex: Integer]: TCaseCount read GetCumulativeDeaths;
    property CumulativeRecovered[AIndex: Integer]: TCaseCount read GetCumulativeRecovered;
    property CumulativeSick[AIndex: Integer]: TCaseCount read GetCumulativeSick;

    property NewConfirmed[AIndex: Integer]: TCaseCount read GetNewConfirmed;
    property NewDeaths[AIndex: Integer]: TCaseCount read GetNewDeaths;
    property NewRecovered[AIndex: Integer]: TCaseCount read GetNewRecovered;
    property NewSick[AIndex: Integer]: TCaseCount read GetNewSick;

    property NormalizedNewConfirmed[AIndex: Integer]: double read GetNormalizedNewConfirmed;
    property NormalizedNewDeaths[AIndex: Integer]: Double read GetNormalizedNewDeaths;
    property NormalizedNewRecovered[AIndex: Integer]: Double read GetNormalizedNewRecovered;
  end;

  TStatusbarEvent = procedure (Sender: TObject; const AMsg1, AMsg2: String) of object;
  TDownloadEvent = procedure (Sender: TObject; const AMsg1, AMsg2: string; APercentage: Integer) of object;

  TcDataSource = class
  private
    FOnDownloadMsg: TDownloadEvent;
    FOnStatusMsg: TStatusbarEvent;
  protected
    FCacheDir: String;
    procedure DoDownloadMsg(const AMsg1, AMsg2: String; APercentage: Integer);
    procedure DoStatusMsg(const AMsg1, AMsg2: String);
  public
    constructor Create(ACacheDir: String); virtual;

    // Downloads the data files from the primary online site to a local cache.
    procedure DownloadToCache; virtual; abstract;

    { Extracts the line with the data value from the cache file associated with
      the clicked tree node }
    function GetDataString(const ACountry, AState, ACity: String; ACaseType: TCaseType;
      out AHeader, ACounts: String): Boolean; virtual; abstract;

    { Loads the locations from the specified cache directory into a treeview.
      Clearing, Begin/EndUpdate is done by the calling routine. }
    function LoadLocations(ATreeView: TTreeView): Boolean; virtual; abstract;

    property OnDownloadMsg: TDownloadEvent read FOnDownloadMsg write FOnDownloadMsg;
    property OnStatusMsg: TStatusbarEvent read FOnStatusMsg write FOnStatusMsg;

  end;

  TcDataSourceClass = class of TcDataSource;


implementation

uses
  Math,
  LazFileUtils;

const
  REFERENCE_POPULATION = 100000;

{ TcDataItem }

function TcDataItem.GetCount(ACaseType: TPrimaryCaseType): Integer;
begin
  case ACaseType of
    pctConfirmed: Result := Length(FConfirmed);
    pctDeaths: Result := Length(FDeaths);
    pctRecovered: Result := Length(FRecovered);
  end;
end;

function TcDataItem.GetCumulativeConfirmed(AIndex: Integer): TCaseCount;
begin
  if (AIndex >= 0) and (AIndex < Length(FConfirmed)) then
    Result := FConfirmed[AIndex]
  else
    Result := 0;
end;

function TcDataItem.GetCumulativeDeaths(AIndex: Integer): TCaseCount;
begin
  if (AIndex >= 0) and (AIndex < Length(FDeaths)) then
    Result := FDeaths[AIndex]
  else
    Result := 0;
end;

function TcDataItem.GetCumulativeRecovered(AIndex: Integer): TCaseCount;
var
  n: Integer;
begin
  n := Length(FRecovered);
  if n = 0 then
    Result := -1
  else
  if Aindex < n then
    Result := FRecovered[AIndex]
  else
    Result := 0;
end;

function TcDataItem.GetCumulativeSick(AIndex: Integer): TCaseCount;
var
  nc, nd, nr: Integer;
begin
  nc := GetCumulativeConfirmed(AIndex);
  nd := GetCumulativeDeaths(AIndex);
  nr := GetCumulativeRecovered(AIndex);   // no recovered for JHU US data
  if nr > 0 then
    Result := nc - nd - nr
  else
    Result := -1;
end;

function TcDataItem.GetDate(AIndex: Integer): TDate;
begin
  Result := FFirstDate + AIndex;
end;

function TcDataItem.GetFirstDate: TDate;
begin
  Result := FFirstDate;
end;

function TcDataItem.GetLastDate: TDate;
begin
  Result := FFirstDate + High(FConfirmed);
end;

function TcDataitem.GetNewConfirmed(AIndex: Integer): TCaseCount;
begin
  if AIndex > 0 then
    Result := GetCumulativeConfirmed(AIndex) - GetCumulativeConfirmed(AIndex-1)
  else
    Result := GetCumulativeConfirmed(0);
end;

function TcDataitem.GetNewDeaths(AIndex: Integer): TCaseCount;
begin
  if AIndex > 0 then
    Result := GetCumulativeDeaths(AIndex) - GetCumulativeDeaths(AIndex-1)
  else
    Result := GetCumulativeDeaths(0);
end;

function TcDataitem.GetNewRecovered(AIndex: Integer): TCaseCount;
begin
  if AIndex > 0 then
    Result := GetCumulativeRecovered(AIndex) - GetCumulativeRecovered(AIndex-1)
  else
    Result := GetCumulativeRecovered(0);
end;

function TcDataitem.GetNewSick(AIndex: Integer): TCaseCount;
begin
  if AIndex > 0 then
    Result := GetCumulativeSick(AIndex) - GetCumulativeSick(AIndex-1)
  else
    Result := GetCumulativeSick(0);
end;

function TcDataItem.GetNormalizedNewConfirmed(AIndex: Integer): Double;
var
  i, j: Integer;
begin
  Result := 0;
  if FPopulation <= 0 then
    exit;
  j := High(FConfirmed);
  for i := AIndex - 6 to AIndex do
    if InRange(i, 0, j) then
      Result := Result + NewConfirmed[i];
  Result := Result / FPopulation * REFERENCE_POPULATION;
end;

function TcDataItem.GetNormalizedNewDeaths(AIndex: Integer): Double;
var
  i, j: Integer;
begin
  Result := 0;
  if FPopulation <= 0 then
    exit;
  j := High(FDeaths);
  for i := AIndex - 6 to AIndex do
    if InRange(i, 0, j) then
      Result := Result + NewDeaths[i];
  Result := Result / FPopulation * REFERENCE_POPULATION;
end;

function TcDataItem.GetNormalizedNewRecovered(AIndex: Integer): Double;
var
  i, j: Integer;
begin
  Result := 0;
  if FPopulation <= 0 then
    exit;
  j := High(FRecovered);
  for i := AIndex - 6 to AIndex do
    if InRange(i, 0, j) then
      Result := Result + NewRecovered[i];
  Result := Result / FPopulation * 100000
end;

function TcDataItem.HasData(ACaseType: TPrimaryCaseType): Boolean;
var
  i: Integer;
begin
  Result := true;
  case ACaseType of
    pctConfirmed:
      for i := 0 to Length(FConfirmed) - 1 do
        if FConfirmed[i] > 0 then exit;
    pctDeaths:
      for i := 0 to Length(FDeaths) - 1 do
        if FDeaths[i] > 0 then exit;
    pctRecovered:
      for i := 0 to Length(FRecovered) - 1 do
        if FRecovered[i] > 0 then exit;
  end;
  Result := false;
end;

procedure TcDataItem.SetCases(AFirstDate: TDate;
  const ACases: TCaseArray; ACaseType: TPrimaryCaseType);
begin
  FFirstDate := AFirstDate;
  case ACaseType of
    pctConfirmed:
      begin
        SetLength(FConfirmed, Length(ACases));
        Move(ACases[0], FConfirmed[0], Length(FConfirmed) * SizeOf(TCaseCount));
      end;
    pctDeaths:
      begin
        SetLength(FDeaths, Length(ACases));
        Move(ACases[0], FDeaths[0], Length(FDeaths) * SizeOf(TCaseCount));
      end;
    pctRecovered:
      begin
        SetLength(FRecovered, Length(ACases));
        Move(ACases[0], FRecovered[0], Length(FRecovered) * Sizeof(TCaseCount));
      end;
  end;
end;


{ TcDataSource }

constructor TcDataSource.Create(ACacheDir: String);
begin
  FCacheDir := AppendPathDelim(ACacheDir);
end;

procedure TcDataSource.DoDownloadMsg(const AMsg1, AMsg2: String;
  APercentage: Integer);
begin
  if Assigned(FOnDownloadMsg) then
    FOnDownloadMsg(Self, AMsg1, AMsg2, APercentage);
end;

procedure TcDataSource.DoStatusMsg(const AMsg1, AMsg2: String);
begin
  if Assigned(FOnStatusMsg) then
    FOnStatusMsg(Self, AMsg1, AMsg2);
end;

end.

