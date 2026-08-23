{*******************************************************************************
  Infra.Schema

  Criacao e limpeza do schema no Firebird.

  O DDL vive aqui, em Pascal, e nao num .sql solto, por um motivo pratico:
  assim o programa e AUTOSSUFICIENTE (roda "--dbcriar" e o banco fica pronto).
  A versao comentada, para leitura, esta em bd/schema.sql - e pode ser
  regerada a qualquer momento com "--dbscript > bd\schema.sql".

  ESTUDO:
    * DDL idempotente: rodar duas vezes nao pode quebrar nada. Aqui isso e
      feito ignorando o erro "ja existe" de cada objeto.
    * Ordem importa: tabela antes da FK que a referencia, view por ultimo.
    * Limpeza respeita a ordem inversa das dependencias.
*******************************************************************************}
unit Infra.Schema;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Core.Types,
  Core.Logger,
  Infra.Database;

type
  TSchema = class
  public
    /// Executa o DDL. Objetos que ja existem sao ignorados.
    class function Aplicar(const AConexao: IConexaoBanco;
      const ALogger: ILogger): Integer; static;
    /// Apaga os DADOS (nao a estrutura), na ordem que as FKs permitem.
    class procedure LimparDados(const AConexao: IConexaoBanco); static;
    /// O script completo, para leitura ou para gravar em arquivo.
    class function Script: string; static;
    /// Garante que o arquivo .fdb exista, criando-o via isql se necessario.
    class function GarantirBanco(const AConfig: TConfigBanco;
      const ALogger: ILogger): Boolean; static;
  end;

implementation

uses
  Winapi.Windows;

const
  { Ordem: sequences -> tabelas sem dependencia -> tabelas dependentes ->
    indices -> views. }
  DDL: array[0..42] of string = (
    'CREATE SEQUENCE GEN_CLIENTES_ID',
    'CREATE SEQUENCE GEN_PRODUTOS_ID',
    'CREATE SEQUENCE GEN_PEDIDOS_ID',
    'CREATE SEQUENCE GEN_PEDIDO_ITENS_ID',
    'CREATE SEQUENCE GEN_MOVIMENTOS_ID',
    'CREATE SEQUENCE GEN_PAGAMENTOS_ID',
    'CREATE SEQUENCE GEN_CENTROS_ID',
    'CREATE SEQUENCE GEN_ESTRUTURA_ID',
    'CREATE SEQUENCE GEN_ROTEIRO_ID',
    'CREATE SEQUENCE GEN_ORDENS_ID',
    'CREATE SEQUENCE GEN_OP_COMPONENTES_ID',
    'CREATE SEQUENCE GEN_OP_OPERACOES_ID',
    'CREATE SEQUENCE GEN_OP_APONTAMENTOS_ID',

    'CREATE TABLE CLIENTES (' +
    '  ID INTEGER NOT NULL,' +
    '  NOME VARCHAR(80) NOT NULL,' +
    '  DOCUMENTO VARCHAR(20),' +
    '  EMAIL VARCHAR(120),' +
    '  TELEFONE VARCHAR(20),' +
    '  CIDADE VARCHAR(60),' +
    '  UF VARCHAR(2),' +
    '  CATEGORIA VARCHAR(20) DEFAULT ''ccComum'' NOT NULL,' +
    '  LIMITECREDITO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  ATIVO BOOLEAN DEFAULT TRUE NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_CLIENTES PRIMARY KEY (ID))',

    'CREATE TABLE PRODUTOS (' +
    '  ID INTEGER NOT NULL,' +
    '  CODIGO VARCHAR(20) NOT NULL,' +
    '  DESCRICAO VARCHAR(100) NOT NULL,' +
    '  CATEGORIA VARCHAR(40),' +
    '  PRECO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  ESTOQUE INTEGER DEFAULT 0 NOT NULL,' +
    '  ESTOQUEMINIMO INTEGER DEFAULT 0 NOT NULL,' +
    '  ATIVO BOOLEAN DEFAULT TRUE NOT NULL,' +
    '  TIPO VARCHAR(20) DEFAULT ''tpRevenda'' NOT NULL,' +
    '  UNIDADE VARCHAR(6) DEFAULT ''UN'' NOT NULL,' +
    '  CUSTOMEDIO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  LEADTIMEDIAS INTEGER DEFAULT 0 NOT NULL,' +
    '  LOTEMINIMO INTEGER DEFAULT 1 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_PRODUTOS PRIMARY KEY (ID),' +
    '  CONSTRAINT UQ_PRODUTOS_CODIGO UNIQUE (CODIGO),' +
    '  CONSTRAINT CK_PRODUTOS_ESTOQUE CHECK (ESTOQUE >= 0))',

    'CREATE TABLE CENTROS_TRABALHO (' +
    '  ID INTEGER NOT NULL,' +
    '  CODIGO VARCHAR(15) NOT NULL,' +
    '  DESCRICAO VARCHAR(60) NOT NULL,' +
    '  CAPACIDADEHORASDIA DOUBLE PRECISION DEFAULT 8 NOT NULL,' +
    '  CUSTOHORA NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  ATIVO BOOLEAN DEFAULT TRUE NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_CENTROS PRIMARY KEY (ID),' +
    '  CONSTRAINT UQ_CENTROS_CODIGO UNIQUE (CODIGO))',

    'CREATE TABLE ESTRUTURA_ITENS (' +
    '  ID INTEGER NOT NULL,' +
    '  PRODUTOPAIID INTEGER NOT NULL,' +
    '  COMPONENTEID INTEGER NOT NULL,' +
    '  CODIGOCOMPONENTE VARCHAR(20),' +
    '  DESCRICAOCOMPONENTE VARCHAR(100),' +
    '  QUANTIDADE DOUBLE PRECISION DEFAULT 1 NOT NULL,' +
    '  PERDAPERCENTUAL DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  SEQUENCIA INTEGER DEFAULT 10 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_ESTRUTURA PRIMARY KEY (ID),' +
    '  CONSTRAINT UQ_ESTRUTURA UNIQUE (PRODUTOPAIID, COMPONENTEID),' +
    '  CONSTRAINT CK_ESTRUTURA_CICLO CHECK (PRODUTOPAIID <> COMPONENTEID),' +
    '  CONSTRAINT CK_ESTRUTURA_QTD CHECK (QUANTIDADE > 0),' +
    '  CONSTRAINT FK_ESTRUTURA_PAI FOREIGN KEY (PRODUTOPAIID) REFERENCES PRODUTOS (ID),' +
    '  CONSTRAINT FK_ESTRUTURA_COMP FOREIGN KEY (COMPONENTEID) REFERENCES PRODUTOS (ID))',

    'CREATE TABLE ROTEIRO_OPERACOES (' +
    '  ID INTEGER NOT NULL,' +
    '  PRODUTOID INTEGER NOT NULL,' +
    '  SEQUENCIA INTEGER NOT NULL,' +
    '  DESCRICAO VARCHAR(60) NOT NULL,' +
    '  CENTROID INTEGER NOT NULL,' +
    '  CODIGOCENTRO VARCHAR(15),' +
    '  TEMPOSETUPMIN DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  TEMPOUNITARIOMIN DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_ROTEIRO PRIMARY KEY (ID),' +
    '  CONSTRAINT UQ_ROTEIRO UNIQUE (PRODUTOID, SEQUENCIA),' +
    '  CONSTRAINT FK_ROTEIRO_PRODUTO FOREIGN KEY (PRODUTOID) REFERENCES PRODUTOS (ID),' +
    '  CONSTRAINT FK_ROTEIRO_CENTRO FOREIGN KEY (CENTROID) REFERENCES CENTROS_TRABALHO (ID))',

    'CREATE TABLE PEDIDOS (' +
    '  ID INTEGER NOT NULL,' +
    '  NUMERO VARCHAR(15) NOT NULL,' +
    '  CLIENTEID INTEGER NOT NULL,' +
    '  NOMECLIENTE VARCHAR(80),' +
    '  STATUS VARCHAR(20) DEFAULT ''spRascunho'' NOT NULL,' +
    '  FORMAPAGAMENTO VARCHAR(20) DEFAULT ''fpPix'' NOT NULL,' +
    '  OBSERVACAO VARCHAR(200),' +
    '  FRETE NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  DESCONTONEGOCIADO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  DATACONFIRMACAO TIMESTAMP,' +
    '  DATAFECHAMENTO TIMESTAMP,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_PEDIDOS PRIMARY KEY (ID),' +
    '  CONSTRAINT FK_PEDIDOS_CLIENTE FOREIGN KEY (CLIENTEID) REFERENCES CLIENTES (ID))',

    'CREATE TABLE PEDIDO_ITENS (' +
    '  ID INTEGER NOT NULL,' +
    '  PEDIDOID INTEGER NOT NULL,' +
    '  PRODUTOID INTEGER NOT NULL,' +
    '  CODIGOPRODUTO VARCHAR(20),' +
    '  DESCRICAOPRODUTO VARCHAR(100),' +
    '  QUANTIDADE INTEGER DEFAULT 1 NOT NULL,' +
    '  PRECOUNITARIO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  DESCONTOPERCENTUAL DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_PEDIDO_ITENS PRIMARY KEY (ID),' +
    '  CONSTRAINT FK_ITENS_PEDIDO FOREIGN KEY (PEDIDOID) ' +
    '    REFERENCES PEDIDOS (ID) ON DELETE CASCADE)',

    'CREATE TABLE PAGAMENTOS (' +
    '  ID INTEGER NOT NULL,' +
    '  PEDIDOID INTEGER NOT NULL,' +
    '  VALOR NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  FORMA VARCHAR(20) DEFAULT ''fpPix'' NOT NULL,' +
    '  AUTORIZADO BOOLEAN DEFAULT FALSE NOT NULL,' +
    '  AUTORIZACAO VARCHAR(60),' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_PAGAMENTOS PRIMARY KEY (ID))',

    'CREATE TABLE ORDENS_PRODUCAO (' +
    '  ID INTEGER NOT NULL,' +
    '  NUMERO VARCHAR(15) NOT NULL,' +
    '  PRODUTOID INTEGER NOT NULL,' +
    '  CODIGOPRODUTO VARCHAR(20),' +
    '  DESCRICAOPRODUTO VARCHAR(100),' +
    '  QUANTIDADEPLANEJADA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADEPRODUZIDA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADEREFUGADA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  STATUS VARCHAR(20) DEFAULT ''opPlanejada'' NOT NULL,' +
    '  DATAPREVISTA TIMESTAMP,' +
    '  DATAINICIO TIMESTAMP,' +
    '  DATAFIM TIMESTAMP,' +
    '  CUSTOMATERIALPREVISTO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  CUSTOMATERIALREAL NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  CUSTOOPERACIONALPREVISTO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  CUSTOOPERACIONALREAL NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  PEDIDOORIGEMID INTEGER DEFAULT 0 NOT NULL,' +
    '  OBSERVACAO VARCHAR(200),' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_ORDENS PRIMARY KEY (ID),' +
    '  CONSTRAINT UQ_ORDENS_NUMERO UNIQUE (NUMERO),' +
    '  CONSTRAINT FK_ORDENS_PRODUTO FOREIGN KEY (PRODUTOID) REFERENCES PRODUTOS (ID))',

    'CREATE TABLE OP_COMPONENTES (' +
    '  ID INTEGER NOT NULL,' +
    '  ORDEMID INTEGER NOT NULL,' +
    '  PRODUTOID INTEGER NOT NULL,' +
    '  CODIGOPRODUTO VARCHAR(20),' +
    '  DESCRICAOPRODUTO VARCHAR(100),' +
    '  QUANTIDADENECESSARIA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADECONSUMIDA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  CUSTOUNITARIO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_OP_COMPONENTES PRIMARY KEY (ID),' +
    '  CONSTRAINT FK_OPCOMP_ORDEM FOREIGN KEY (ORDEMID) ' +
    '    REFERENCES ORDENS_PRODUCAO (ID) ON DELETE CASCADE)',

    'CREATE TABLE OP_OPERACOES (' +
    '  ID INTEGER NOT NULL,' +
    '  ORDEMID INTEGER NOT NULL,' +
    '  SEQUENCIA INTEGER NOT NULL,' +
    '  DESCRICAO VARCHAR(60),' +
    '  CENTROID INTEGER NOT NULL,' +
    '  CODIGOCENTRO VARCHAR(15),' +
    '  TEMPOPREVISTOMIN DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  TEMPOREALIZADOMIN DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADEBOA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADEREFUGO DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  CUSTOHORA NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  STATUS VARCHAR(20) DEFAULT ''soPendente'' NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_OP_OPERACOES PRIMARY KEY (ID),' +
    '  CONSTRAINT FK_OPOPER_ORDEM FOREIGN KEY (ORDEMID) ' +
    '    REFERENCES ORDENS_PRODUCAO (ID) ON DELETE CASCADE)',

    'CREATE TABLE OP_APONTAMENTOS (' +
    '  ID INTEGER NOT NULL,' +
    '  ORDEMID INTEGER NOT NULL,' +
    '  SEQUENCIAOPERACAO INTEGER NOT NULL,' +
    '  QUANTIDADEBOA DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  QUANTIDADEREFUGO DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  TEMPOMINUTOS DOUBLE PRECISION DEFAULT 0 NOT NULL,' +
    '  OPERADOR VARCHAR(40),' +
    '  MOTIVOREFUGO VARCHAR(60),' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_OP_APONTAMENTOS PRIMARY KEY (ID),' +
    '  CONSTRAINT FK_OPAP_ORDEM FOREIGN KEY (ORDEMID) ' +
    '    REFERENCES ORDENS_PRODUCAO (ID) ON DELETE CASCADE)',

    'CREATE TABLE MOVIMENTOS_ESTOQUE (' +
    '  ID INTEGER NOT NULL,' +
    '  PRODUTOID INTEGER NOT NULL,' +
    '  CODIGOPRODUTO VARCHAR(20),' +
    '  TIPO VARCHAR(20) NOT NULL,' +
    '  QUANTIDADE INTEGER DEFAULT 0 NOT NULL,' +
    '  SALDORESULTANTE INTEGER DEFAULT 0 NOT NULL,' +
    '  MOTIVO VARCHAR(80),' +
    '  PEDIDOID INTEGER DEFAULT 0 NOT NULL,' +
    '  ORDEMPRODUCAOID INTEGER DEFAULT 0 NOT NULL,' +
    '  CUSTOUNITARIO NUMERIC(15,4) DEFAULT 0 NOT NULL,' +
    '  CRIADOEM TIMESTAMP,' +
    '  ATUALIZADOEM TIMESTAMP,' +
    '  CONSTRAINT PK_MOVIMENTOS PRIMARY KEY (ID))',

    'CREATE INDEX IX_PEDIDOS_CLIENTE ON PEDIDOS (CLIENTEID)',
    'CREATE INDEX IX_PEDIDOS_STATUS ON PEDIDOS (STATUS)',
    'CREATE INDEX IX_ITENS_PEDIDO ON PEDIDO_ITENS (PEDIDOID)',
    'CREATE INDEX IX_PAGAMENTOS_PEDIDO ON PAGAMENTOS (PEDIDOID)',
    'CREATE INDEX IX_MOV_PRODUTO ON MOVIMENTOS_ESTOQUE (PRODUTOID)',
    'CREATE INDEX IX_MOV_ORDEM ON MOVIMENTOS_ESTOQUE (ORDEMPRODUCAOID)',
    'CREATE INDEX IX_ESTRUTURA_PAI ON ESTRUTURA_ITENS (PRODUTOPAIID)',
    'CREATE INDEX IX_ESTRUTURA_COMP ON ESTRUTURA_ITENS (COMPONENTEID)',
    'CREATE INDEX IX_ROTEIRO_PRODUTO ON ROTEIRO_OPERACOES (PRODUTOID)',
    'CREATE INDEX IX_ORDENS_STATUS ON ORDENS_PRODUCAO (STATUS)',
    'CREATE INDEX IX_ORDENS_PRODUTO ON ORDENS_PRODUCAO (PRODUTOID)',
    'CREATE INDEX IX_OPCOMP_ORDEM ON OP_COMPONENTES (ORDEMID)',
    'CREATE INDEX IX_OPOPER_ORDEM ON OP_OPERACOES (ORDEMID)',
    'CREATE INDEX IX_OPAP_ORDEM ON OP_APONTAMENTOS (ORDEMID)',

    'CREATE VIEW VW_ESTOQUE_CRITICO (CODIGO, DESCRICAO, TIPO, ESTOQUE, ' +
    '  ESTOQUEMINIMO, FALTA, VALOR_REPOSICAO) AS ' +
    'SELECT P.CODIGO, P.DESCRICAO, P.TIPO, P.ESTOQUE, P.ESTOQUEMINIMO, ' +
    '       P.ESTOQUEMINIMO - P.ESTOQUE, ' +
    '       (P.ESTOQUEMINIMO - P.ESTOQUE) * P.CUSTOMEDIO ' +
    '  FROM PRODUTOS P WHERE P.ATIVO = TRUE AND P.ESTOQUE < P.ESTOQUEMINIMO',

    'CREATE VIEW VW_ESTRUTURA_EXPLODIDA (RAIZ_ID, NIVEL, COMPONENTE_ID, ' +
    '  CODIGO, DESCRICAO, TIPO, QUANTIDADE) AS ' +
    'WITH RECURSIVE ARVORE (RAIZ_ID, NIVEL, COMPONENTE_ID, QUANTIDADE) AS (' +
    '  SELECT E.PRODUTOPAIID, 0, E.COMPONENTEID, ' +
    '         E.QUANTIDADE / (1 - E.PERDAPERCENTUAL) FROM ESTRUTURA_ITENS E ' +
    '  UNION ALL ' +
    '  SELECT A.RAIZ_ID, A.NIVEL + 1, F.COMPONENTEID, ' +
    '         A.QUANTIDADE * (F.QUANTIDADE / (1 - F.PERDAPERCENTUAL)) ' +
    '    FROM ARVORE A JOIN ESTRUTURA_ITENS F ON F.PRODUTOPAIID = A.COMPONENTE_ID ' +
    '   WHERE A.NIVEL < 12) ' +
    'SELECT A.RAIZ_ID, A.NIVEL, A.COMPONENTE_ID, P.CODIGO, P.DESCRICAO, ' +
    '       P.TIPO, A.QUANTIDADE ' +
    '  FROM ARVORE A JOIN PRODUTOS P ON P.ID = A.COMPONENTE_ID',

    'CREATE VIEW VW_EFICIENCIA_CENTRO (CODIGOCENTRO, OPERACOES, ' +
    '  TEMPO_PREVISTO, TEMPO_REALIZADO, EFICIENCIA) AS ' +
    'SELECT O.CODIGOCENTRO, COUNT(*), SUM(O.TEMPOPREVISTOMIN), ' +
    '       SUM(O.TEMPOREALIZADOMIN), ' +
    '       CASE WHEN SUM(O.TEMPOREALIZADOMIN) > 0 ' +
    '            THEN SUM(O.TEMPOPREVISTOMIN) / SUM(O.TEMPOREALIZADOMIN) ' +
    '            ELSE 0 END ' +
    '  FROM OP_OPERACOES O WHERE O.TEMPOREALIZADOMIN > 0 ' +
    ' GROUP BY O.CODIGOCENTRO'
  );

  /// Ordem INVERSA das dependencias: filho antes do pai.
  TABELAS_LIMPEZA: array[0..12] of string = (
    'MOVIMENTOS_ESTOQUE', 'OP_APONTAMENTOS', 'OP_OPERACOES', 'OP_COMPONENTES',
    'ORDENS_PRODUCAO', 'PAGAMENTOS', 'PEDIDO_ITENS', 'PEDIDOS',
    'ROTEIRO_OPERACOES', 'ESTRUTURA_ITENS', 'CENTROS_TRABALHO',
    'PRODUTOS', 'CLIENTES'
  );

function ExecutarEsperando(const AComando, AParametros: string): Boolean;
var
  LInfo: TStartupInfo;
  LProcesso: TProcessInformation;
  LLinha: string;
begin
  LLinha := Format('"%s" %s', [AComando, AParametros]);
  FillChar(LInfo, SizeOf(LInfo), 0);
  LInfo.cb := SizeOf(LInfo);
  LInfo.dwFlags := STARTF_USESHOWWINDOW;
  LInfo.wShowWindow := SW_HIDE;

  Result := CreateProcess(nil, PChar(LLinha), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, LInfo, LProcesso);
  if not Result then
    Exit;
  try
    WaitForSingleObject(LProcesso.hProcess, 60000);
  finally
    CloseHandle(LProcesso.hThread);
    CloseHandle(LProcesso.hProcess);
  end;
end;

{ TSchema }

class function TSchema.Script: string;
var
  LComando: string;
  LBuilder: TStringBuilder;
begin
  LBuilder := TStringBuilder.Create;
  try
    for LComando in DDL do
      LBuilder.Append(LComando).AppendLine(';').AppendLine;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

class function TSchema.Aplicar(const AConexao: IConexaoBanco;
  const ALogger: ILogger): Integer;
var
  LComando: string;
  LLogger: ILogger;
begin
  Result := 0;
  if Assigned(ALogger) then
    LLogger := ALogger
  else
    LLogger := TLoggerNulo.Create;

  AConexao.Conectar;

  for LComando in DDL do
  try
    AConexao.Executar(LComando, []);
    Inc(Result);
  except
    on E: Exception do
      { Idempotencia: se o objeto ja existe, seguimos em frente. Qualquer
        outro erro e problema de verdade e precisa aparecer. }
      if E.Message.Contains('already exists') or
         E.Message.Contains('ja existe') or
         E.Message.Contains('unsuccessful metadata update') then
        LLogger.Debug('DDL ignorado (ja existe): %s', [Copy(LComando, 1, 60)])
      else
        raise EInfra.CreateFmt('Falha no DDL: %s'#13#10'Comando: %s',
          [E.Message, Copy(LComando, 1, 120)]);
  end;

  LLogger.Info('Schema aplicado: %d objeto(s) criado(s).', [Result]);
end;

class procedure TSchema.LimparDados(const AConexao: IConexaoBanco);
var
  LTabela: string;
begin
  AConexao.Conectar;
  for LTabela in TABELAS_LIMPEZA do
    AConexao.Executar('DELETE FROM ' + LTabela, []);
end;

class function TSchema.GarantirBanco(const AConfig: TConfigBanco;
  const ALogger: ILogger): Boolean;
var
  LPastaFb, LIsql, LScript, LArquivoTmp: string;
  LLogger: ILogger;
begin
  if Assigned(ALogger) then
    LLogger := ALogger
  else
    LLogger := TLoggerNulo.Create;

  // So conseguimos criar o arquivo se o servidor for esta maquina.
  if TFile.Exists(AConfig.Caminho) then
    Exit(True);

  if not SameText(AConfig.Servidor, 'localhost') and
     not SameText(AConfig.Servidor, '127.0.0.1') then
  begin
    LLogger.Aviso('O banco nao existe e o servidor e remoto: crie-o no servidor.');
    Exit(False);
  end;

  { isql.exe fica na pasta raiz da instalacao. VendorLib aponta para
    ...\Firebird_5_0\WOW64\fbclient.dll -> subimos um nivel. }
  LPastaFb := TPath.GetDirectoryName(AConfig.VendorLib);
  if SameText(TPath.GetFileName(LPastaFb), 'WOW64') then
    LPastaFb := TPath.GetDirectoryName(LPastaFb);
  LIsql := TPath.Combine(LPastaFb, 'isql.exe');

  if not TFile.Exists(LIsql) then
  begin
    LLogger.Aviso('isql.exe nao encontrado em "%s": crie o banco a mao.',
      [LPastaFb]);
    Exit(False);
  end;

  if not TDirectory.Exists(TPath.GetDirectoryName(AConfig.Caminho)) then
    TDirectory.CreateDirectory(TPath.GetDirectoryName(AConfig.Caminho));

  LScript := Format(
    'CREATE DATABASE ''%s/%d:%s'' USER ''%s'' PASSWORD ''%s'' ' +
    'PAGE_SIZE 8192 DEFAULT CHARACTER SET UTF8;',
    [AConfig.Servidor, AConfig.Porta, AConfig.Caminho,
     AConfig.Usuario, AConfig.Senha]);

  LArquivoTmp := TPath.Combine(TPath.GetTempPath, 'criar_erp_fdb.sql');
  TFile.WriteAllText(LArquivoTmp, LScript, TEncoding.ASCII);
  try
    ExecutarEsperando(LIsql, Format('-q -i "%s"', [LArquivoTmp]));
  finally
    if TFile.Exists(LArquivoTmp) then
      TFile.Delete(LArquivoTmp);
  end;

  Result := TFile.Exists(AConfig.Caminho);
  if Result then
    LLogger.Info('Banco criado em "%s".', [AConfig.Caminho])
  else
    LLogger.Erro('Nao foi possivel criar o banco em "%s".', [AConfig.Caminho]);
end;

end.
