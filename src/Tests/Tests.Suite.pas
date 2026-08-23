{*******************************************************************************
  Tests.Suite

  Os testes do sistema. Leia-os como DOCUMENTACAO EXECUTAVEL: cada teste
  descreve, em uma frase, uma regra de negocio ou um comportamento tecnico.

  ESTUDO - repare nas tres naturezas de teste aqui:
    * unitario     -> testa uma classe isolada (TPedido, TEspec, TContainer)
    * de integracao-> monta a aplicacao inteira e exercita um fluxo real
    * com dublê    -> troca o gateway real por um que sempre recusa, para
                      testar o caminho de erro sem depender de sorte

  Rode com:  GestaoComercial.exe --testes
*******************************************************************************}
unit Tests.Suite;

interface

uses
  Tests.Framework;

/// Monta a suite. Com AIncluirBanco, acrescenta os testes que exigem
/// um Firebird no ar (rode com "--testes --db").
function RodarTodosOsTestes(AIncluirBanco: Boolean = False): Boolean;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  Core.Types,
  Core.Logger,
  Core.Events,
  Core.Container,
  Core.Validation,
  Core.Json,
  Domain.Entities,
  Domain.Enums,
  Domain.Events,
  Domain.Interfaces,
  Domain.Services,
  Domain.Specifications,
  Domain.Producao,
  Domain.Producao.Services,
  Infra.Repositories,
  Infra.UnitOfWork,
  Infra.Gateway,
  Infra.Persistence,
  Infra.Database,
  Infra.Schema,
  App.Bootstrap,
  App.Seed,
  App.Reports;

{ ---------------------------------------------------------------- auxiliares }

type
  /// Evento so para testes do barramento.
  TEventoTeste = class(TEventoDominio)
  private
    FValor: Integer;
  public
    constructor Create(AValor: Integer); reintroduce;
    property Valor: Integer read FValor;
  end;

  TEventoTesteFilho = class(TEventoTeste);

constructor TEventoTeste.Create(AValor: Integer);
begin
  inherited Create;
  FValor := AValor;
end;

/// Cria uma aplicacao silenciosa, executa o bloco e destroi tudo.
procedure ComApp(const ABloco: TProc<TAplicacao>);
var
  LApp: TAplicacao;
begin
  LApp := TAplicacao.Create(True,
    TPath.Combine(TPath.GetTempPath, 'gestao_comercial_testes'));
  try
    ABloco(LApp);
  finally
    LApp.Free;
  end;
end;

function CriarCliente(const ANome: string; ALimite: Currency;
  ACategoria: TCategoriaCliente = ccComum): TCliente;
begin
  Result := TCliente.Create;
  Result.Nome := ANome;
  Result.Documento := '52998224725';
  Result.Email := 'teste@email.com';
  Result.LimiteCredito := ALimite;
  Result.Categoria := ACategoria;
end;

function CriarProduto(const ACodigo: string; APreco: Currency;
  AEstoque: Integer): TProduto;
begin
  Result := TProduto.Create;
  Result.Codigo := ACodigo;
  Result.Descricao := 'Produto ' + ACodigo;
  Result.Categoria := 'Testes';
  Result.Preco := APreco;
  Result.Estoque := AEstoque;
  Result.EstoqueMinimo := 2;
end;

type
  /// Uma fabrica minima para os testes de PCP.
  TFabricaTeste = record
    Centro: TCentroTrabalho;
    MateriaPrima: TProduto;
    Acabado: TProduto;
  end;

{ Numeros escolhidos para dar contas redondas:
    - materia-prima custa 10, e o acabado leva 2 -> material = 20/unidade
    - centro custa 60/hora = 1 por minuto, operacao gasta 5 min/peca
      -> transformacao = 5/unidade
    - custo padrao = 25 por unidade }
function MontarFabrica(AApp: TAplicacao;
  AEstoqueMateriaPrima: Integer = 100): TFabricaTeste;
begin
  Result.Centro := TCentroTrabalho.Create;
  Result.Centro.Codigo := 'CT-1';
  Result.Centro.Descricao := 'Centro de teste';
  Result.Centro.CustoHora := 60;
  AApp.Centros.Adicionar(Result.Centro);

  Result.MateriaPrima := CriarProduto('MP-1', 20, AEstoqueMateriaPrima);
  Result.MateriaPrima.Tipo := tpMateriaPrima;
  Result.MateriaPrima.CustoMedio := 10;
  AApp.Produtos.Adicionar(Result.MateriaPrima);

  Result.Acabado := CriarProduto('PA-1', 100, 0);
  Result.Acabado.Tipo := tpAcabado;
  AApp.Produtos.Adicionar(Result.Acabado);

  AApp.Engenharia.DefinirComponente(Result.Acabado.Id,
    Result.MateriaPrima.Id, 2);
  AApp.Engenharia.DefinirOperacao(Result.Acabado.Id, 10, 'Montagem',
    Result.Centro.Id, 0, 5);
end;

{ ---------------------------------------------------------------- Firebird }

/// Config apontando para um banco SEPARADO, para nao mexer no ERP.FDB real.
function ConfigDeTeste: string;
var
  LConfig: TConfigBanco;
begin
  LConfig := TConfigBanco.DoArquivo(ArquivoConfigPadrao);
  LConfig.Caminho := TPath.Combine(TPath.GetDirectoryName(LConfig.Caminho),
    'ERP_TESTES.FDB');
  Result := TPath.Combine(TPath.GetTempPath, 'firebird_testes.ini');
  LConfig.GravarEm(Result);
end;

/// Aplicacao ligada ao banco de testes, com as tabelas vazias.
procedure ComAppBanco(const ABloco: TProc<TAplicacao>; ALimpar: Boolean = True);
var
  LApp: TAplicacao;
begin
  LApp := TAplicacao.Create(True, '', mpFirebird, ConfigDeTeste);
  try
    TSchema.GarantirBanco(LApp.ConfigBanco, nil);
    TSchema.Aplicar(LApp.Banco, nil);
    if ALimpar then
      TSchema.LimparDados(LApp.Banco);
    ABloco(LApp);
  finally
    LApp.Free;
  end;
end;

procedure RegistrarTestesDeBanco(ASuite: TSuiteTestes);
begin
  ASuite.Grupo('Firebird / Persistencia real');

  ASuite.Teste('Conecta no Firebird e encontra o schema',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        begin
          TVerificar.EhVerdade(AApp.Banco.Conectado, 'deveria estar conectado');
          TVerificar.EhVerdade(AApp.Banco.SchemaCriado, 'schema criado');
        end);
    end);

  ASuite.Teste('Grava e le de volta todos os tipos de campo (RTTI)',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LCliente: TCliente;
          LId: Integer;
          LLimite: Currency;
        begin
          LCliente := CriarCliente('Cliente Firebird', 12345, ccOuro);
          LCliente.Cidade := 'Santos';
          LCliente.UF := 'SP';
          LCliente.Ativo := False;
          AApp.Clientes.Adicionar(LCliente);
          LId := LCliente.Id;
          LLimite := 12345;

          TVerificar.EhVerdade(LId > 0, 'o generator deve ter dado um Id');
          TVerificar.Igual(1, AApp.Clientes.Contar, 'um registro gravado');

          // Segunda aplicacao: le do banco, sem nada em memoria.
          ComAppBanco(
            procedure(AOutra: TAplicacao)
            var
              LLido: TCliente;
            begin
              LLido := AOutra.Clientes.PorId(LId);
              TVerificar.Igual('Cliente Firebird', LLido.Nome, 'string');
              TVerificar.Igual(LLimite, LLido.LimiteCredito, 'Currency');
              TVerificar.EhVerdade(LLido.Categoria = ccOuro, 'enumerado');
              TVerificar.EhFalso(LLido.Ativo, 'boolean');
              TVerificar.EhVerdade(LLido.CriadoEm > 0, 'timestamp');
            end, False);
        end);
    end);

  ASuite.Teste('Identity map: duas leituras devolvem o MESMO objeto',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LProduto: TProduto;
          LA, LB: TProduto;
        begin
          LProduto := AApp.Produtos.Adicionar(CriarProduto('IDM', 10, 5));
          LA := AApp.Produtos.PorId(LProduto.Id);
          LB := AApp.Produtos.PorId(LProduto.Id);

          TVerificar.EhVerdade(Pointer(LA) = Pointer(LB),
            'o mapa de identidade deve devolver a mesma instancia');
          LA.Estoque := 42;
          TVerificar.Igual(42, LB.Estoque,
            'alterar por uma referencia reflete na outra');
        end);
    end);

  ASuite.Teste('Agregado: pedido grava e recarrega os itens',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LCliente: TCliente;
          LProduto: TProduto;
          LPedido: TPedido;
          LId: Integer;
          LTotal: Currency;
        begin
          LCliente := AApp.Clientes.Adicionar(CriarCliente('Cli', 100000));
          LProduto := AApp.Produtos.Adicionar(CriarProduto('P-AG', 100, 50));

          LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
          AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 3);
          AApp.Vendas.ConfirmarPedido(LPedido.Id);
          LId := LPedido.Id;
          LTotal := LPedido.TotalLiquido;

          ComAppBanco(
            procedure(AOutra: TAplicacao)
            var
              LLido: TPedido;
            begin
              LLido := AOutra.Pedidos.PorId(LId);
              TVerificar.Igual(1, LLido.Itens.Count, 'item recarregado');
              TVerificar.Igual(3, LLido.Itens[0].Quantidade, 'quantidade');
              TVerificar.Igual(LTotal, LLido.TotalLiquido, 'total preservado');
              TVerificar.EhVerdade(LLido.Status = spConfirmado, 'status');
            end, False);
        end);
    end);

  ASuite.Teste('Agregado: ordem de producao grava as tres colecoes filhas',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LFabrica: TFabricaTeste;
          LOrdem: TOrdemProducao;
          LId: Integer;
        begin
          LFabrica := MontarFabrica(AApp);
          LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
          AApp.Producao.LiberarOrdem(LOrdem.Id);
          AApp.Producao.Apontar(LOrdem.Id, 10, 2, 0, 10, 'operador');
          LId := LOrdem.Id;

          ComAppBanco(
            procedure(AOutra: TAplicacao)
            var
              LLida: TOrdemProducao;
            begin
              LLida := AOutra.Ordens.PorId(LId);
              TVerificar.Igual(1, LLida.Componentes.Count, 'componentes');
              TVerificar.Igual(1, LLida.Operacoes.Count, 'operacoes');
              TVerificar.Igual(1, LLida.Apontamentos.Count, 'apontamentos');
              TVerificar.EhVerdade(LLida.Status = opEmProducao, 'status');
              TVerificar.EhVerdade(Abs(LLida.QuantidadeProduzida - 2) < 0.001,
                'quantidade produzida');
            end, False);
        end);
    end);

  ASuite.Teste('Estrutura e roteiro persistem e a explosao funciona pelo banco',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LFabrica: TFabricaTeste;
          LId: Integer;
        begin
          LFabrica := MontarFabrica(AApp);
          LId := LFabrica.Acabado.Id;

          ComAppBanco(
            procedure(AOutra: TAplicacao)
            var
              LExplosao: TArray<TLinhaExplosao>;
              LEsperado: Currency;
            begin
              LExplosao := AOutra.Engenharia.Explodir(LId, 5);
              TVerificar.Igual(1, Length(LExplosao), 'uma linha de estrutura');
              TVerificar.EhVerdade(
                Abs(LExplosao[0].QuantidadeTotal - 10) < 0.001,
                '5 unidades x 2 componentes');

              LEsperado := 25;
              TVerificar.Igual(LEsperado, AOutra.Engenharia.CustoPadrao(LId),
                'custo padrao recalculado a partir do banco');
            end, False);
        end);
    end);

  ASuite.Teste('Rollback desfaz no banco E no objeto em memoria',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LProduto: TProduto;
          LId: Integer;
        begin
          LProduto := AApp.Produtos.Adicionar(CriarProduto('ROLL', 10, 100));
          LId := LProduto.Id;

          TVerificar.Lanca(EDominio,
            procedure
            begin
              AApp.UoW.Executar(
                procedure
                begin
                  AApp.Estoque.RequisitarParaOrdem(LId, 30, 0, 'teste');
                  raise EDominio.Create('falha proposital no meio');
                end);
            end, 'o erro deve propagar');

          TVerificar.Igual(100, LProduto.Estoque,
            'o objeto em memoria voltou ao saldo original');

          ComAppBanco(
            procedure(AOutra: TAplicacao)
            begin
              TVerificar.Igual(100, AOutra.Produtos.PorId(LId).Estoque,
                'o banco tambem voltou ao saldo original');
            end, False);
        end);
    end);

  ASuite.Teste('Remover apaga o pai e os filhos em cascata',
    procedure
    begin
      ComAppBanco(
        procedure(AApp: TAplicacao)
        var
          LCliente: TCliente;
          LProduto: TProduto;
          LPedido: TPedido;
          LId: Integer;
        begin
          LCliente := AApp.Clientes.Adicionar(CriarCliente('Cli', 100000));
          LProduto := AApp.Produtos.Adicionar(CriarProduto('P-DEL', 10, 50));
          LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
          AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 2);
          LId := LPedido.Id;

          AApp.Pedidos.Remover(LId);

          TVerificar.Igual(0, AApp.Pedidos.Contar, 'pedido apagado');
          TVerificar.Igual(0,
            AApp.Banco.ValorEscalar(
              'SELECT COUNT(*) FROM PEDIDO_ITENS WHERE PEDIDOID = :P', [LId]),
            'itens apagados junto (ON DELETE CASCADE)');
        end);
    end);
end;

{ ------------------------------------------------------------------- suite }

function RodarTodosOsTestes(AIncluirBanco: Boolean): Boolean;
var
  LSuite: TSuiteTestes;
begin
  LSuite := TSuiteTestes.Create;
  try
    // ======================================================= CORE / TIPOS
    LSuite.Grupo('Core / Tipos');

    LSuite.Teste('TResultado.Ok carrega o valor e marca sucesso',
      procedure
      var
        LResultado: TResultado<Integer>;
      begin
        LResultado := TResultado<Integer>.Ok(42);
        TVerificar.EhVerdade(LResultado.Sucesso, 'deveria ser sucesso');
        TVerificar.Igual(42, LResultado.Valor, 'valor');
        TVerificar.Igual('', LResultado.Erro, 'erro deve estar vazio');
      end);

    LSuite.Teste('TResultado.Falha nao carrega valor e ValorOu devolve o padrao',
      procedure
      var
        LResultado: TResultado<Integer>;
      begin
        LResultado := TResultado<Integer>.Falha('deu ruim');
        TVerificar.EhFalso(LResultado.Sucesso, 'nao deveria ser sucesso');
        TVerificar.Igual('deu ruim', LResultado.Erro, 'mensagem de erro');
        TVerificar.Igual(7, LResultado.ValorOu(7), 'valor padrao');
      end);

    LSuite.Teste('ValorOuFalhar converte falha em excecao',
      procedure
      begin
        TVerificar.Lanca(EDominio,
          procedure
          var
            LResultado: TResultado<Integer>;
          begin
            LResultado := TResultado<Integer>.Falha('x');
            LResultado.ValorOuFalhar;
          end, 'deveria lancar EDominio');
      end);

    LSuite.Teste('TEnumUtils converte enum para texto e de volta',
      procedure
      var
        LTexto: string;
      begin
        LTexto := TEnumUtils.ParaTexto<TStatusPedido>(spEnviado);
        TVerificar.Igual('spEnviado', LTexto, 'nome do enum');
        TVerificar.EhVerdade(TEnumUtils.DoTexto<TStatusPedido>(LTexto) = spEnviado,
          'volta para o mesmo valor');
        TVerificar.Igual(6, TEnumUtils.Contagem<TStatusPedido>, 'quantidade de estados');
      end);

    // =================================================== CORE / VALIDACAO
    LSuite.Grupo('Core / Validacao por atributos');

    LSuite.Teste('Cliente bem preenchido nao gera erros',
      procedure
      var
        LCliente: TCliente;
      begin
        LCliente := CriarCliente('Empresa Teste Ltda', 1000);
        try
          TVerificar.Igual(0, Length(LCliente.Erros), 'nenhum erro esperado');
        finally
          LCliente.Free;
        end;
      end);

    LSuite.Teste('Nome vazio dispara [Obrigatorio] e [TamanhoMin]',
      procedure
      var
        LCliente: TCliente;
        LErros: TArray<string>;
      begin
        LCliente := CriarCliente('', 1000);
        try
          LErros := LCliente.Erros;
          TVerificar.Igual(2, Length(LErros), 'dois erros no nome');
          TVerificar.Contem(LErros[0], 'Nome', 'o rotulo deve aparecer no erro');
        finally
          LCliente.Free;
        end;
      end);

    LSuite.Teste('E-mail malformado e recusado pelo atributo [Email]',
      procedure
      var
        LCliente: TCliente;
      begin
        LCliente := CriarCliente('Fulano de Tal', 100);
        try
          LCliente.Email := 'fulano-arroba-email';
          TVerificar.Igual(1, Length(LCliente.Erros), 'um erro de e-mail');
          TVerificar.Contem(LCliente.Erros[0], 'e-mail', 'mensagem de e-mail');
        finally
          LCliente.Free;
        end;
      end);

    LSuite.Teste('Validar() lanca EValidacao com a lista de problemas',
      procedure
      var
        LProduto: TProduto;
      begin
        LProduto := TProduto.Create;
        try
          TVerificar.Lanca(EValidacao,
            procedure
            begin
              LProduto.Validar; // sem codigo, sem descricao, preco zero
            end, 'produto vazio deve falhar');
        finally
          LProduto.Free;
        end;
      end);

    // =================================================== CORE / CONTAINER
    LSuite.Grupo('Core / Container de dependencias');

    LSuite.Teste('Singleton devolve sempre a mesma instancia',
      procedure
      var
        LContainer: IContainer;
        LA, LB: ILogger;
      begin
        LContainer := TContainer.Create;
        TDI.Registrar<ILogger>(LContainer,
          function(const C: IContainer): IInterface
          begin
            Result := TMemoriaLogger.Create;
          end, esSingleton);

        LA := TDI.Resolver<ILogger>(LContainer);
        LB := TDI.Resolver<ILogger>(LContainer);
        TVerificar.EhVerdade(LA = LB, 'deveria ser a mesma instancia');

        { Limpar() antes de sair NAO e frescura: a fabrica escrita aqui dentro
          e um metodo anonimo aninhado, e todo metodo anonimo carrega uma
          referencia ao frame de locais deste bloco -- frame que contem
          LContainer. Container -> fabrica -> frame -> LContainer -> container:
          ciclo. Limpar() solta as fabricas e desfaz o ciclo.
          (No sistema real isso nao acontece: veja App.Bootstrap.) }
        LContainer.Limpar;
      end);

    LSuite.Teste('Transiente devolve instancias diferentes',
      procedure
      var
        LContainer: IContainer;
        LA, LB: ILogger;
      begin
        LContainer := TContainer.Create;
        TDI.Registrar<ILogger>(LContainer,
          function(const C: IContainer): IInterface
          begin
            Result := TMemoriaLogger.Create;
          end, esTransiente);

        LA := TDI.Resolver<ILogger>(LContainer);
        LB := TDI.Resolver<ILogger>(LContainer);
        TVerificar.EhFalso(LA = LB, 'deveriam ser instancias distintas');
        LContainer.Limpar;   // desfaz o ciclo fabrica <-> frame (ver teste acima)
      end);

    LSuite.Teste('Resolver servico nao registrado lanca EConfiguracao',
      procedure
      var
        LContainer: IContainer;
      begin
        LContainer := TContainer.Create;
        TVerificar.Lanca(EConfiguracao,
          procedure
          begin
            TDI.Resolver<ILogger>(LContainer);
          end, 'deveria reclamar do registro ausente');
        LContainer.Limpar;
      end);

    LSuite.Teste('Dependencia circular e detectada em vez de estourar a pilha',
      procedure
      var
        LContainer: IContainer;
      begin
        LContainer := TContainer.Create;
        // ILogger depende de ILogger: ciclo proposital.
        TDI.Registrar<ILogger>(LContainer,
          function(const C: IContainer): IInterface
          begin
            Result := TDI.Resolver<ILogger>(C);
          end, esTransiente);

        TVerificar.Lanca(EConfiguracao,
          procedure
          begin
            TDI.Resolver<ILogger>(LContainer);
          end, 'deveria detectar o ciclo');
        LContainer.Limpar;
      end);

    // ===================================================== CORE / EVENTOS
    LSuite.Grupo('Core / Barramento de eventos');

    LSuite.Teste('Assinante recebe o evento publicado',
      procedure
      var
        LBus: IEventBus;
        LRecebido: Integer;
      begin
        LRecebido := 0;
        LBus := TEventBus.Create(nil);
        TEventos.Assinar<TEventoTeste>(LBus,
          procedure(AEvento: TEventoTeste)
          begin
            LRecebido := AEvento.Valor;
          end);

        LBus.Publicar(TEventoTeste.Create(99));
        TVerificar.Igual(99, LRecebido, 'valor recebido pelo assinante');
        TVerificar.Igual(1, LBus.TotalPublicados, 'total publicado');

        { Mesmo motivo do LContainer.Limpar nos testes do container:
          barramento -> handler -> frame de locais -> LBus -> barramento. }
        LBus.LimparAssinantes;
      end);

    LSuite.Teste('Assinante da classe base recebe eventos das classes filhas',
      procedure
      var
        LBus: IEventBus;
        LContador: Integer;
      begin
        LContador := 0;
        LBus := TEventBus.Create(nil);
        TEventos.Assinar<TEventoDominio>(LBus,
          procedure(AEvento: TEventoDominio)
          begin
            Inc(LContador);
          end);

        LBus.Publicar(TEventoTeste.Create(1));
        LBus.Publicar(TEventoTesteFilho.Create(2));
        TVerificar.Igual(2, LContador, 'os dois eventos devem chegar');
        LBus.LimparAssinantes;
      end);

    LSuite.Teste('Assinante que estoura nao impede os demais',
      procedure
      var
        LBus: IEventBus;
        LSegundoRodou: Boolean;
      begin
        LSegundoRodou := False;
        LBus := TEventBus.Create(nil);

        TEventos.Assinar<TEventoTeste>(LBus,
          procedure(AEvento: TEventoTeste)
          begin
            raise EDominio.Create('falha proposital');
          end, 'quebrado');

        TEventos.Assinar<TEventoTeste>(LBus,
          procedure(AEvento: TEventoTeste)
          begin
            LSegundoRodou := True;
          end, 'saudavel');

        TVerificar.NaoLanca(
          procedure
          begin
            LBus.Publicar(TEventoTeste.Create(1));
          end, 'Publicar nao deve propagar erro de assinante');

        TVerificar.EhVerdade(LSegundoRodou, 'o segundo assinante deve rodar');
        LBus.LimparAssinantes;
      end);

    // ================================================== DOMINIO / PEDIDO
    LSuite.Grupo('Dominio / Pedido (agregado)');

    LSuite.Teste('Total do item considera desconto percentual',
      procedure
      var
        LPedido: TPedido;
        LProduto: TProduto;
        LEsperado: Currency;
      begin
        LPedido := TPedido.Create;
        LProduto := CriarProduto('X1', 100, 10);
        try
          LProduto.Id := 1;
          LPedido.AdicionarItem(LProduto, 3, 0.10);
          LEsperado := 270; // 3 x 100 - 10%
          TVerificar.Igual(LEsperado, LPedido.TotalLiquido, 'total com desconto');
          TVerificar.Igual(3, LPedido.QuantidadeItens, 'quantidade de pecas');
        finally
          LProduto.Free;
          LPedido.Free;
        end;
      end);

    LSuite.Teste('Adicionar o mesmo produto soma a quantidade, sem duplicar linha',
      procedure
      var
        LPedido: TPedido;
        LProduto: TProduto;
      begin
        LPedido := TPedido.Create;
        LProduto := CriarProduto('X1', 50, 100);
        try
          LProduto.Id := 1;
          LPedido.AdicionarItem(LProduto, 2);
          LPedido.AdicionarItem(LProduto, 3);
          TVerificar.Igual(1, LPedido.Itens.Count, 'uma unica linha');
          TVerificar.Igual(5, LPedido.Itens[0].Quantidade, 'quantidade somada');
        finally
          LProduto.Free;
          LPedido.Free;
        end;
      end);

    LSuite.Teste('Pedido fora de rascunho recusa alteracao de itens',
      procedure
      var
        LPedido: TPedido;
        LProduto: TProduto;
      begin
        LPedido := TPedido.Create;
        LProduto := CriarProduto('X1', 50, 100);
        try
          LProduto.Id := 1;
          LPedido.AdicionarItem(LProduto, 1);
          LPedido.MudarStatus(spConfirmado);

          TVerificar.Lanca(EDominio,
            procedure
            begin
              LPedido.AdicionarItem(LProduto, 1);
            end, 'nao pode alterar pedido confirmado');
        finally
          LProduto.Free;
          LPedido.Free;
        end;
      end);

    LSuite.Teste('Maquina de estados aceita o caminho feliz e recusa saltos',
      procedure
      var
        LPedido: TPedido;
      begin
        LPedido := TPedido.Create;
        try
          TVerificar.EhVerdade(LPedido.PodeMudarPara(spConfirmado), 'rascunho->confirmado');
          TVerificar.EhFalso(LPedido.PodeMudarPara(spEnviado), 'rascunho->enviado e invalido');

          LPedido.MudarStatus(spConfirmado);
          LPedido.MudarStatus(spPago);
          LPedido.MudarStatus(spEnviado);
          LPedido.MudarStatus(spEntregue);

          TVerificar.EhFalso(LPedido.PodeMudarPara(spCancelado),
            'entregue e estado final');
          TVerificar.Lanca(EDominio,
            procedure
            begin
              LPedido.MudarStatus(spCancelado);
            end, 'transicao a partir de estado final deve falhar');
        finally
          LPedido.Free;
        end;
      end);

    LSuite.Teste('Produto recusa saida maior que o saldo',
      procedure
      var
        LProduto: TProduto;
      begin
        LProduto := CriarProduto('X1', 10, 5);
        try
          TVerificar.Lanca(EDominio,
            procedure
            begin
              LProduto.MovimentarEstoque(tmSaida, 6);
            end, 'estoque insuficiente');
          TVerificar.Igual(5, LProduto.Estoque, 'saldo nao pode ter mudado');
        finally
          LProduto.Free;
        end;
      end);

    LSuite.Teste('Clone do pedido e copia profunda (itens independentes)',
      procedure
      var
        LOriginal, LCopia: TPedido;
        LProduto: TProduto;
      begin
        LOriginal := TPedido.Create;
        LProduto := CriarProduto('X1', 100, 10);
        try
          LProduto.Id := 1;
          LOriginal.Numero := 'PED-00001';
          LOriginal.AdicionarItem(LProduto, 2);

          LCopia := TPedido(LOriginal.Clone);
          try
            TVerificar.Igual('PED-00001', LCopia.Numero, 'numero copiado');
            TVerificar.Igual(1, LCopia.Itens.Count, 'item copiado');

            LCopia.Itens[0].Quantidade := 99;
            TVerificar.Igual(2, LOriginal.Itens[0].Quantidade,
              'o original nao pode ser afetado');
          finally
            LCopia.Free;
          end;
        finally
          LProduto.Free;
          LOriginal.Free;
        end;
      end);

    LSuite.Teste('Pedido sobrevive a ida e volta para JSON',
      procedure
      var
        LOriginal, LRestaurado: TPedido;
        LProduto: TProduto;
        LJson: TJSONObject;
      begin
        LOriginal := TPedido.Create;
        LProduto := CriarProduto('X1', 123.45, 10);
        try
          LProduto.Id := 7;
          LOriginal.Id := 33;
          LOriginal.Numero := 'PED-00033';
          LOriginal.NomeCliente := 'Cliente JSON';
          LOriginal.AdicionarItem(LProduto, 2, 0.10);
          LOriginal.MudarStatus(spConfirmado);

          LJson := LOriginal.ToJson;
          try
            LRestaurado := TPedido.Create;
            try
              LRestaurado.FromJson(LJson);
              TVerificar.Igual(33, LRestaurado.Id, 'Id');
              TVerificar.Igual('PED-00033', LRestaurado.Numero, 'numero');
              TVerificar.EhVerdade(LRestaurado.Status = spConfirmado, 'status');
              TVerificar.Igual(1, LRestaurado.Itens.Count, 'itens');
              TVerificar.Igual(7, LRestaurado.Itens[0].ProdutoId, 'produto do item');
              TVerificar.Igual(LOriginal.TotalLiquido, LRestaurado.TotalLiquido,
                'total preservado');
            finally
              LRestaurado.Free;
            end;
          finally
            LJson.Free;
          end;
        finally
          LProduto.Free;
          LOriginal.Free;
        end;
      end);

    // ============================================ DOMINIO / SPECIFICATIONS
    LSuite.Grupo('Dominio / Specifications');

    LSuite.Teste('Composicao E / OU / NAO funciona como esperado',
      procedure
      var
        LProduto: TProduto;
        LAtivo, LBaixo: ISpecification<TProduto>;
      begin
        LProduto := CriarProduto('X1', 10, 1); // minimo 2 -> abaixo do minimo
        try
          LAtivo := TProdutoAtivo.Create;
          LBaixo := TProdutoAbaixoMinimo.Create;

          TVerificar.EhVerdade(LAtivo.Satisfeita(LProduto), 'esta ativo');
          TVerificar.EhVerdade(LBaixo.Satisfeita(LProduto), 'esta abaixo do minimo');
          TVerificar.EhVerdade(TProdutoAtivo.Create.E(LBaixo).Satisfeita(LProduto),
            'ativo E abaixo');
          TVerificar.EhFalso(TProdutoAtivo.Create.Nao.Satisfeita(LProduto),
            'NAO ativo deve ser falso');

          LProduto.Ativo := False;
          TVerificar.EhFalso(TProdutoAtivo.Create.E(LBaixo).Satisfeita(LProduto),
            'inativo derruba o E');
          TVerificar.EhVerdade(TProdutoAtivo.Create.Ou(LBaixo).Satisfeita(LProduto),
            'mas o OU continua verdadeiro');
        finally
          LProduto.Free;
        end;
      end);

    LSuite.Teste('Specification a partir de metodo anonimo',
      procedure
      var
        LProduto: TProduto;
        LEspec: ISpecification<TProduto>;
      begin
        LProduto := CriarProduto('X1', 500, 3);
        try
          LEspec := TEspecDe<TProduto>.Nova(
            function(const AItem: TProduto): Boolean
            begin
              Result := AItem.Preco > 400;
            end, 'caro');
          TVerificar.EhVerdade(LEspec.Satisfeita(LProduto), 'produto caro');
          TVerificar.Igual('caro', LEspec.Nome, 'nome da specification');
        finally
          LProduto.Free;
        end;
      end);

    // =============================================== INFRA / REPOSITORIOS
    LSuite.Grupo('Infra / Repositorios');

    LSuite.Teste('Adicionar gera Ids sequenciais e Contar acompanha',
      procedure
      var
        LRepo: IRepositorioProdutos;
        LA, LB: TProduto;
      begin
        LRepo := TRepositorioProdutos.Create;
        LA := LRepo.Adicionar(CriarProduto('A', 10, 1));
        LB := LRepo.Adicionar(CriarProduto('B', 20, 2));
        TVerificar.Igual(1, LA.Id, 'primeiro Id');
        TVerificar.Igual(2, LB.Id, 'segundo Id');
        TVerificar.Igual(2, LRepo.Contar, 'total no repositorio');
      end);

    LSuite.Teste('Id preexistente e respeitado (carga de arquivo)',
      procedure
      var
        LRepo: IRepositorioProdutos;
        LProduto: TProduto;
      begin
        LRepo := TRepositorioProdutos.Create;
        LProduto := CriarProduto('A', 10, 1);
        LProduto.Id := 50;
        LRepo.Adicionar(LProduto);
        // o proximo gerado deve continuar de 51
        TVerificar.Igual(51, LRepo.Adicionar(CriarProduto('B', 10, 1)).Id,
          'sequencia deve continuar apos o maior Id');
      end);

    LSuite.Teste('PorId inexistente lanca ENaoEncontrado',
      procedure
      var
        LRepo: IRepositorioProdutos;
      begin
        LRepo := TRepositorioProdutos.Create;
        TVerificar.Lanca(ENaoEncontrado,
          procedure
          begin
            LRepo.PorId(123);
          end, 'id inexistente');
      end);

    LSuite.Teste('Buscar filtra pela specification e Remover apaga',
      procedure
      var
        LRepo: IRepositorioProdutos;
        LProduto: TProduto;
        LCaros: ISpecification<TProduto>;
      begin
        LRepo := TRepositorioProdutos.Create;
        LRepo.Adicionar(CriarProduto('BARATO', 10, 10));
        LProduto := LRepo.Adicionar(CriarProduto('CARO', 5000, 10));

        LCaros := TProdutoAcimaDe.Create(1000);
        TVerificar.Igual(1, Length(LRepo.Buscar(LCaros)), 'so um produto caro');

        LRepo.Remover(LProduto.Id);
        TVerificar.Igual(1, LRepo.Contar, 'sobrou um produto');
        TVerificar.Igual(0, Length(LRepo.Buscar(LCaros)), 'o caro foi removido');
      end);

    LSuite.Teste('PorCodigo encontra ignorando maiusculas/minusculas',
      procedure
      var
        LRepo: IRepositorioProdutos;
      begin
        LRepo := TRepositorioProdutos.Create;
        LRepo.Adicionar(CriarProduto('SSD-1TB', 500, 5));
        TVerificar.NaoNulo(LRepo.PorCodigo('ssd-1tb'), 'busca case-insensitive');
        TVerificar.Nulo(LRepo.PorCodigo('NAO-EXISTE'), 'codigo inexistente');
      end);

    // ================================================ INFRA / UNIT OF WORK
    LSuite.Grupo('Infra / Unit of Work');

    LSuite.Teste('Rollback desfaz as operacoes na ordem inversa',
      procedure
      var
        LUoW: IUnitOfWork;
        LOrdem: TStringList;
      begin
        LOrdem := TStringList.Create;
        try
          LUoW := TUnitOfWork.Create(nil);
          LUoW.Iniciar;
          LUoW.RegistrarDesfazer(
            procedure
            begin
              LOrdem.Add('primeira');
            end, 'op1');
          LUoW.RegistrarDesfazer(
            procedure
            begin
              LOrdem.Add('segunda');
            end, 'op2');

          TVerificar.Igual(2, LUoW.OperacoesPendentes, 'duas compensacoes');
          LUoW.Rollback;

          TVerificar.Igual('segunda', LOrdem[0], 'a ultima e desfeita primeiro');
          TVerificar.Igual('primeira', LOrdem[1], 'depois a primeira');
          TVerificar.EhFalso(LUoW.EmTransacao, 'transacao encerrada');
        finally
          LOrdem.Free;
        end;
      end);

    LSuite.Teste('Executar faz commit e limpa as compensacoes',
      procedure
      var
        LUoW: IUnitOfWork;
      begin
        LUoW := TUnitOfWork.Create(nil);
        LUoW.Executar(
          procedure
          begin
            LUoW.RegistrarDesfazer(
              procedure
              begin
              end, 'op');
          end);
        TVerificar.Igual(0, LUoW.OperacoesPendentes, 'nada pendente apos commit');
        TVerificar.EhFalso(LUoW.EmTransacao, 'fora de transacao');
      end);

    LSuite.Teste('Excecao dentro de Executar dispara rollback e propaga o erro',
      procedure
      var
        LUoW: IUnitOfWork;
        LDesfez: Boolean;
      begin
        LDesfez := False;
        LUoW := TUnitOfWork.Create(nil);

        TVerificar.Lanca(EDominio,
          procedure
          begin
            LUoW.Executar(
              procedure
              begin
                LUoW.RegistrarDesfazer(
                  procedure
                  begin
                    LDesfez := True;
                  end, 'op');
                raise EDominio.Create('falha no meio da transacao');
              end);
          end, 'o erro deve chegar ao chamador');

        TVerificar.EhVerdade(LDesfez, 'a compensacao deve ter rodado');
      end);

    // ==================================================== SERVICOS (fluxo)
    LSuite.Grupo('Servicos / Fluxo de vendas');

    LSuite.Teste('Confirmar pedido baixa estoque, aplica desconto e muda status',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
            LResultado: TResultado<Currency>;
            LEsperado: Currency;
          begin
            LCliente := AApp.Clientes.Adicionar(
              CriarCliente('Cliente Ouro', 100000, ccOuro));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 1000, 10));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 4);

            LResultado := AApp.Vendas.ConfirmarPedido(LPedido.Id);

            TVerificar.EhVerdade(LResultado.Sucesso, 'confirmacao deve dar certo');
            TVerificar.EhVerdade(LPedido.Status = spConfirmado, 'status confirmado');
            TVerificar.Igual(6, LProduto.Estoque, 'estoque baixado de 10 para 6');
            // 4 x 1000 = 4000; melhor desconto = categoria Ouro (6%) = 240
            LEsperado := 3760;
            TVerificar.Igual(LEsperado, LResultado.Valor, 'total com desconto');
          end);
      end);

    LSuite.Teste('Sem estoque suficiente a confirmacao falha sem efeitos colaterais',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
            LResultado: TResultado<Currency>;
          begin
            LCliente := AApp.Clientes.Adicionar(CriarCliente('Cliente', 100000));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 100, 3));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 10);

            LResultado := AApp.Vendas.ConfirmarPedido(LPedido.Id);

            TVerificar.EhFalso(LResultado.Sucesso, 'deveria falhar');
            TVerificar.Contem(LResultado.Erro, 'Estoque', 'motivo da falha');
            TVerificar.Igual(3, LProduto.Estoque, 'estoque intacto');
            TVerificar.EhVerdade(LPedido.Status = spRascunho, 'continua em rascunho');
          end);
      end);

    LSuite.Teste('Limite de credito insuficiente bloqueia a confirmacao',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
            LResultado: TResultado<Currency>;
          begin
            LCliente := AApp.Clientes.Adicionar(CriarCliente('Pequeno', 500));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 1000, 10));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 2);

            LResultado := AApp.Vendas.ConfirmarPedido(LPedido.Id);

            TVerificar.EhFalso(LResultado.Sucesso, 'deveria faltar credito');
            TVerificar.Contem(LResultado.Erro, 'Credito', 'motivo da falha');
            TVerificar.Igual(10, LProduto.Estoque, 'estoque nao foi tocado');
          end);
      end);

    LSuite.Teste('Cancelar pedido confirmado devolve o estoque reservado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
          begin
            LCliente := AApp.Clientes.Adicionar(CriarCliente('Cliente', 100000));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 100, 20));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 5);
            AApp.Vendas.ConfirmarPedido(LPedido.Id);
            TVerificar.Igual(15, LProduto.Estoque, 'estoque reservado');

            AApp.Vendas.CancelarPedido(LPedido.Id, 'desistencia do cliente');

            TVerificar.Igual(20, LProduto.Estoque, 'estoque devolvido');
            TVerificar.EhVerdade(LPedido.Status = spCancelado, 'status cancelado');
          end);
      end);

    LSuite.Teste('Pagamento recusado pelo gateway mantem o pedido confirmado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
            LResultado: TResultado<string>;
          begin
            // DUBLÊ: troca a implementacao ANTES de o servico ser criado.
            TDI.RegistrarInstancia<IGatewayPagamento>(AApp.Container,
              TGatewaySempreRecusa.Create);

            LCliente := AApp.Clientes.Adicionar(CriarCliente('Cliente', 100000));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 100, 20));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 2);
            AApp.Vendas.ConfirmarPedido(LPedido.Id);

            LResultado := AApp.Vendas.PagarPedido(LPedido.Id, fpPix);

            TVerificar.EhFalso(LResultado.Sucesso, 'pagamento deve ser recusado');
            TVerificar.EhVerdade(LPedido.Status = spConfirmado,
              'o pedido nao pode virar Pago');
            TVerificar.Igual(1, Length(AApp.Pagamentos.DoPedido(LPedido.Id)),
              'a tentativa recusada fica registrada');
          end);
      end);

    LSuite.Teste('Fluxo completo: confirmar -> pagar -> enviar -> entregar',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
          begin
            LCliente := AApp.Clientes.Adicionar(CriarCliente('Cliente', 100000));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 100, 20));

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 2);

            TVerificar.EhVerdade(AApp.Vendas.ConfirmarPedido(LPedido.Id).Sucesso,
              'confirmacao');
            TVerificar.EhVerdade(AApp.Vendas.PagarPedido(LPedido.Id, fpPix).Sucesso,
              'pagamento');
            AApp.Vendas.EnviarPedido(LPedido.Id);
            AApp.Vendas.EntregarPedido(LPedido.Id);

            TVerificar.EhVerdade(LPedido.Status = spEntregue, 'status final');
          end);
      end);

    LSuite.Teste('Politica composta escolhe o desconto mais vantajoso',
      procedure
      var
        LPolitica: TPoliticaMelhorDesconto;
        LPedido: TPedido;
        LProduto: TProduto;
        LCliente: TCliente;
        LDesconto, LEsperado: Currency;
      begin
        LPolitica := TPoliticaMelhorDesconto.Create([
          TPoliticaCategoria.Create,              // Prata = 3%
          TPoliticaValor.Create(5000, 0.07)       // acima de 5000 = 7%
        ]);
        LPedido := TPedido.Create;
        LProduto := CriarProduto('P1', 1000, 100);
        LCliente := CriarCliente('Cliente Prata', 100000, ccPrata);
        try
          LProduto.Id := 1;
          LPedido.AdicionarItem(LProduto, 10); // bruto 10.000

          LDesconto := LPolitica.Calcular(LPedido, LCliente);
          LEsperado := 700;
          TVerificar.Igual(LEsperado, LDesconto, '7% deve ganhar dos 3%');
          TVerificar.Contem(LPolitica.UltimaEscolhida, 'valor',
            'a politica por valor deve ter sido a escolhida');
        finally
          LPolitica.Free;   // ninguem guardou interface para ela
          LCliente.Free;
          LProduto.Free;
          LPedido.Free;
        end;
      end);

    LSuite.Teste('Evento de estoque baixo e publicado ao reservar',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LCliente: TCliente;
            LProduto: TProduto;
            LPedido: TPedido;
            LAvisos: Integer;
          begin
            LAvisos := 0;
            TEventos.Assinar<TEstoqueBaixo>(AApp.Eventos,
              procedure(AEvento: TEstoqueBaixo)
              begin
                Inc(LAvisos);
              end, 'contador-teste');

            LCliente := AApp.Clientes.Adicionar(CriarCliente('Cliente', 100000));
            LProduto := AApp.Produtos.Adicionar(CriarProduto('P1', 10, 5));
            // minimo = 2; vender 4 deixa saldo 1 -> abaixo do minimo

            LPedido := AApp.Vendas.CriarPedido(LCliente.Id);
            AApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 4);
            AApp.Vendas.ConfirmarPedido(LPedido.Id);

            TVerificar.Igual(1, LAvisos, 'um aviso de estoque baixo');
          end);
      end);

    // ========================================================= RELATORIOS
    LSuite.Grupo('Relatorios');

    LSuite.Teste('Painel geral e curva ABC rodam sobre os dados de exemplo',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LRelatorios: TRelatorios;
            LLinhas: TArray<string>;
          begin
            TSeed.Popular(AApp);
            LRelatorios := TRelatorios.Create(AApp);
            try
              LLinhas := LRelatorios.PainelGeral;
              TVerificar.EhVerdade(Length(LLinhas) > 5, 'painel deve ter linhas');

              LLinhas := LRelatorios.CurvaABC;
              TVerificar.EhVerdade(Length(LLinhas) > 5, 'curva ABC deve ter linhas');

              LLinhas := LRelatorios.TopProdutos(3);
              TVerificar.EhVerdade(Length(LLinhas) > 3, 'ranking deve ter linhas');
            finally
              LRelatorios.Free;
            end;
          end);
      end);

    LSuite.Teste('Dados de exemplo produzem o estado esperado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          begin
            TSeed.Popular(AApp);
            TVerificar.Igual(5, AApp.Clientes.Contar, 'clientes');
            // 8 itens de revenda + 7 itens da fabrica (5 MP, 1 semi, 1 acabado)
            TVerificar.Igual(15, AApp.Produtos.Contar, 'produtos');
            TVerificar.Igual(4, AApp.Pedidos.Contar, 'pedidos');
            TVerificar.EhVerdade(Length(AApp.Produtos.AbaixoDoMinimo) > 0,
              'ha produtos a repor');
          end);
      end);

    // ======================================================== PERSISTENCIA
    LSuite.Grupo('Persistencia');

    LSuite.Teste('Salvar e recarregar preserva clientes, produtos e pedidos',
      procedure
      var
        LPasta: string;
        LClientes, LProdutos, LPedidos: Integer;
        LTotalPedido: Currency;
      begin
        LPasta := TPath.Combine(TPath.GetTempPath, 'gc_teste_persistencia');
        if TDirectory.Exists(LPasta) then
          TDirectory.Delete(LPasta, True);

        LClientes := 0;
        LProdutos := 0;
        LPedidos := 0;
        LTotalPedido := 0;

        // 1a aplicacao: popula e salva
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LArmazem: IArmazenamento;
          begin
            TSeed.Popular(AApp);
            LClientes := AApp.Clientes.Contar;
            LProdutos := AApp.Produtos.Contar;
            LPedidos := AApp.Pedidos.Contar;
            LTotalPedido := AApp.Pedidos.PorId(1).TotalLiquido;

            LArmazem := TArmazenamentoJson.Create(LPasta,
              AApp.Clientes, AApp.Produtos, AApp.Pedidos,
              AApp.Movimentos, AApp.Pagamentos, nil);
            LArmazem.SalvarTudo;
          end);

        // 2a aplicacao: carrega do disco e compara
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LArmazem: IArmazenamento;
          begin
            LArmazem := TArmazenamentoJson.Create(LPasta,
              AApp.Clientes, AApp.Produtos, AApp.Pedidos,
              AApp.Movimentos, AApp.Pagamentos, nil);
            TVerificar.EhVerdade(LArmazem.CarregarTudo, 'deveria carregar algo');

            TVerificar.Igual(LClientes, AApp.Clientes.Contar, 'clientes');
            TVerificar.Igual(LProdutos, AApp.Produtos.Contar, 'produtos');
            TVerificar.Igual(LPedidos, AApp.Pedidos.Contar, 'pedidos');
            TVerificar.Igual(LTotalPedido, AApp.Pedidos.PorId(1).TotalLiquido,
              'total do pedido 1 preservado');
            TVerificar.EhVerdade(AApp.Pedidos.PorId(1).Itens.Count > 0,
              'itens do pedido preservados');
          end);

        if TDirectory.Exists(LPasta) then
          TDirectory.Delete(LPasta, True);
      end);

    // ==================================================== PCP / ENGENHARIA
    LSuite.Grupo('PCP / Engenharia de produto');

    LSuite.Teste('Estrutura circular direta (item que leva a si mesmo) e recusada',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
          begin
            LFabrica := MontarFabrica(AApp);
            TVerificar.Lanca(EDominio,
              procedure
              begin
                AApp.Engenharia.DefinirComponente(LFabrica.Acabado.Id,
                  LFabrica.Acabado.Id, 1);
              end, 'A nao pode levar A');
          end);
      end);

    LSuite.Teste('Estrutura circular indireta (A leva B, B leva A) e recusada',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LA, LB, LC: TProduto;
          begin
            LA := AApp.Produtos.Adicionar(CriarProduto('A', 10, 0));
            LA.Tipo := tpAcabado;
            LB := AApp.Produtos.Adicionar(CriarProduto('B', 10, 0));
            LB.Tipo := tpIntermediario;
            LC := AApp.Produtos.Adicionar(CriarProduto('C', 10, 0));
            LC.Tipo := tpIntermediario;

            AApp.Engenharia.DefinirComponente(LA.Id, LB.Id, 1);
            AApp.Engenharia.DefinirComponente(LB.Id, LC.Id, 1);

            TVerificar.EhVerdade(AApp.Engenharia.CriariaCiclo(LC.Id, LA.Id),
              'C levar A fecharia o ciclo A->B->C->A');
            TVerificar.Lanca(EDominio,
              procedure
              begin
                AApp.Engenharia.DefinirComponente(LC.Id, LA.Id, 1);
              end, 'ciclo indireto deve ser recusado');
          end);
      end);

    LSuite.Teste('Explosao multinivel multiplica as quantidades dos dois niveis',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LMesa, LTampo, LChapa: TProduto;
            LExplosao: TArray<TLinhaExplosao>;
            LLinha: TLinhaExplosao;
            LQtdChapa: Double;
          begin
            LMesa := AApp.Produtos.Adicionar(CriarProduto('MESA', 100, 0));
            LMesa.Tipo := tpAcabado;
            LTampo := AApp.Produtos.Adicionar(CriarProduto('TAMPO', 50, 0));
            LTampo.Tipo := tpIntermediario;
            LChapa := AApp.Produtos.Adicionar(CriarProduto('CHAPA', 20, 0));
            LChapa.Tipo := tpMateriaPrima;

            // 1 mesa leva 2 tampos; 1 tampo leva 3 chapas -> 6 chapas por mesa
            AApp.Engenharia.DefinirComponente(LMesa.Id, LTampo.Id, 2);
            AApp.Engenharia.DefinirComponente(LTampo.Id, LChapa.Id, 3);

            LExplosao := AApp.Engenharia.Explodir(LMesa.Id, 10);
            LQtdChapa := 0;
            for LLinha in LExplosao do
              if LLinha.Codigo = 'CHAPA' then
                LQtdChapa := LLinha.QuantidadeTotal;

            TVerificar.Igual(2, Length(LExplosao), 'duas linhas na arvore');
            TVerificar.EhVerdade(Abs(LQtdChapa - 60) < 0.001,
              Format('10 mesas precisam de 60 chapas (obteve %.4f)', [LQtdChapa]));
          end);
      end);

    LSuite.Teste('Perda tecnica aumenta a quantidade bruta requisitada',
      procedure
      var
        LItem: TItemEstrutura;
      begin
        LItem := TItemEstrutura.Create;
        try
          LItem.Quantidade := 1;
          LItem.PerdaPercentual := 0.2;   // 20% de perda
          // Para sobrar 1 apos perder 20%, e preciso separar 1,25.
          TVerificar.EhVerdade(Abs(LItem.QuantidadeBruta - 1.25) < 0.0001,
            Format('quantidade bruta deveria ser 1,25 (obteve %.4f)',
              [LItem.QuantidadeBruta]));
        finally
          LItem.Free;
        end;
      end);

    LSuite.Teste('Custo padrao acumula material e transformacao (roll-up)',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LEsperado: Currency;
          begin
            LFabrica := MontarFabrica(AApp);
            // material 2 x 10 = 20 ; transformacao 5 min x 1/min = 5
            LEsperado := 25;
            TVerificar.Igual(LEsperado,
              AApp.Engenharia.CustoPadrao(LFabrica.Acabado.Id),
              'custo padrao do acabado');
          end);
      end);

    LSuite.Teste('Item comprado nao aceita estrutura',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LComprado, LOutro: TProduto;
          begin
            LComprado := AApp.Produtos.Adicionar(CriarProduto('COMP', 10, 0));
            LComprado.Tipo := tpMateriaPrima;
            LOutro := AApp.Produtos.Adicionar(CriarProduto('X', 10, 0));

            TVerificar.Lanca(EDominio,
              procedure
              begin
                AApp.Engenharia.DefinirComponente(LComprado.Id, LOutro.Id, 1);
              end, 'materia-prima nao tem receita');
          end);
      end);

    // ===================================================== PCP / PRODUCAO
    LSuite.Grupo('PCP / Ordem de producao');

    LSuite.Teste('Criar ordem congela estrutura, roteiro e custo previsto',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LResultado: TResultado<TOrdemProducao>;
            LOrdem: TOrdemProducao;
            LEsperado: Currency;
          begin
            LFabrica := MontarFabrica(AApp);
            LResultado := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date);

            TVerificar.EhVerdade(LResultado.Sucesso, 'ordem deve ser criada');
            LOrdem := LResultado.Valor;
            TVerificar.Igual(1, LOrdem.Componentes.Count, 'um componente');
            TVerificar.Igual(1, LOrdem.Operacoes.Count, 'uma operacao');
            TVerificar.EhVerdade(
              Abs(LOrdem.Componentes[0].QuantidadeNecessaria - 6) < 0.001,
              '3 unidades x 2 de componente = 6');

            LEsperado := 75;   // 3 x (20 material + 5 transformacao)
            TVerificar.Igual(LEsperado, LOrdem.CustoPrevisto, 'custo previsto');

            { A engenharia muda DEPOIS: a ordem ja aberta nao pode mudar. }
            AApp.Engenharia.DefinirComponente(LFabrica.Acabado.Id,
              LFabrica.MateriaPrima.Id, 99);
            TVerificar.EhVerdade(
              Abs(LOrdem.Componentes[0].QuantidadeNecessaria - 6) < 0.001,
              'a estrutura da ordem esta congelada');
          end);
      end);

    LSuite.Teste('Ordem de item comprado e recusada',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LComprado: TProduto;
            LResultado: TResultado<TOrdemProducao>;
          begin
            LComprado := AApp.Produtos.Adicionar(CriarProduto('COMP', 10, 5));
            LComprado.Tipo := tpMateriaPrima;
            LResultado := AApp.Producao.CriarOrdem(LComprado.Id, 1, Date);
            TVerificar.EhFalso(LResultado.Sucesso, 'nao se fabrica o que se compra');
            TVerificar.Contem(LResultado.Erro, 'Materia-prima', 'motivo');
          end);
      end);

    LSuite.Teste('Ordem de item sem estrutura e recusada',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LAcabado: TProduto;
            LResultado: TResultado<TOrdemProducao>;
          begin
            LAcabado := AApp.Produtos.Adicionar(CriarProduto('PA-X', 100, 0));
            LAcabado.Tipo := tpAcabado;
            LResultado := AApp.Producao.CriarOrdem(LAcabado.Id, 1, Date);
            TVerificar.EhFalso(LResultado.Sucesso, 'sem receita nao ha ordem');
            TVerificar.Contem(LResultado.Erro, 'estrutura', 'motivo');
          end);
      end);

    LSuite.Teste('Liberar a ordem requisita o material do estoque',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LResultado: TResultado<Currency>;
            LEsperado: Currency;
          begin
            LFabrica := MontarFabrica(AApp, 100);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;

            LResultado := AApp.Producao.LiberarOrdem(LOrdem.Id);

            TVerificar.EhVerdade(LResultado.Sucesso, 'liberacao deve dar certo');
            TVerificar.Igual(94, LFabrica.MateriaPrima.Estoque,
              '100 - 6 requisitados');
            TVerificar.EhVerdade(LOrdem.Status = opLiberada, 'status liberada');
            LEsperado := 60;   // 6 x 10
            TVerificar.Igual(LEsperado, LResultado.Valor, 'custo do material');
          end);
      end);

    LSuite.Teste('Sem material a liberacao falha e nada e movimentado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LResultado: TResultado<Currency>;
          begin
            LFabrica := MontarFabrica(AApp, 3);   // precisa de 6, tem 3
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;

            LResultado := AApp.Producao.LiberarOrdem(LOrdem.Id);

            TVerificar.EhFalso(LResultado.Sucesso, 'deve faltar material');
            TVerificar.Contem(LResultado.Erro, 'MP-1', 'o item em falta');
            TVerificar.Igual(3, LFabrica.MateriaPrima.Estoque, 'estoque intacto');
            TVerificar.EhVerdade(LOrdem.Status = opPlanejada, 'segue planejada');
          end);
      end);

    LSuite.Teste('Apontar na ultima operacao da entrada do acabado no estoque',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LResultado: TResultado<Double>;
            LCustoPadrao: Currency;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);

            LResultado := AApp.Producao.Apontar(LOrdem.Id, 10, 3, 0, 15, 'joao');

            TVerificar.EhVerdade(LResultado.Sucesso, 'apontamento aceito');
            TVerificar.Igual(3, LFabrica.Acabado.Estoque, 'acabado entrou');
            TVerificar.EhVerdade(LOrdem.Status = opEmProducao, 'virou em producao');
            LCustoPadrao := 25;   // 75 previstos / 3 unidades
            TVerificar.Igual(LCustoPadrao, LFabrica.Acabado.CustoMedio,
              'entrada pelo custo padrao');
          end);
      end);

    LSuite.Teste('Apontar mais que o planejado e recusado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LResultado: TResultado<Double>;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);

            LResultado := AApp.Producao.Apontar(LOrdem.Id, 10, 5, 0, 20, 'joao');
            TVerificar.EhFalso(LResultado.Sucesso, 'nao pode passar do planejado');
            TVerificar.Igual(0, LFabrica.Acabado.Estoque, 'nada entrou');
          end);
      end);

    LSuite.Teste('Refugo sem motivo informado e recusado',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);

            TVerificar.Lanca(EDominio,
              procedure
              begin
                AApp.Producao.Apontar(LOrdem.Id, 10, 1, 1, 10, 'joao', '');
              end, 'refugo exige motivo');
          end);
      end);

    LSuite.Teste('Concluir a ordem apura variacao de custo e indice de refugo',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LFecho: TResultado<TFechamentoOP>;
            LZero: Currency;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);
            // 3 boas no tempo exatamente previsto (15 min) -> variacao zero
            AApp.Producao.Apontar(LOrdem.Id, 10, 3, 0, 15, 'joao');

            LFecho := AApp.Producao.ConcluirOrdem(LOrdem.Id);

            TVerificar.EhVerdade(LFecho.Sucesso, 'conclusao aceita');
            LZero := 0;
            TVerificar.Igual(LZero, LFecho.Valor.Variacao,
              'sem variacao: realizado igual ao previsto');
            TVerificar.EhVerdade(LOrdem.Status = opConcluida, 'status concluida');
          end);
      end);

    LSuite.Teste('Ordem mais lenta que o previsto gera variacao positiva',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
            LFecho: TResultado<TFechamentoOP>;
            LEsperado: Currency;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);
            // gastou 25 min em vez de 15 -> 10 minutos a mais x 1/min = +10
            AApp.Producao.Apontar(LOrdem.Id, 10, 3, 0, 25, 'joao');

            LFecho := AApp.Producao.ConcluirOrdem(LOrdem.Id);
            LEsperado := 10;
            TVerificar.Igual(LEsperado, LFecho.Valor.Variacao,
              'a demora extra vira custo');
          end);
      end);

    LSuite.Teste('Cancelar ordem liberada devolve o material ao estoque',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem: TOrdemProducao;
          begin
            LFabrica := MontarFabrica(AApp, 100);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);
            TVerificar.Igual(94, LFabrica.MateriaPrima.Estoque, 'material saiu');

            AApp.Producao.CancelarOrdem(LOrdem.Id, 'teste');

            TVerificar.Igual(100, LFabrica.MateriaPrima.Estoque, 'material voltou');
            TVerificar.EhVerdade(LOrdem.Status = opCancelada, 'status cancelada');
          end);
      end);

    LSuite.Teste('Ordem de producao sobrevive a ida e volta para JSON',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LFabrica: TFabricaTeste;
            LOrdem, LRestaurada: TOrdemProducao;
            LJson: TJSONObject;
          begin
            LFabrica := MontarFabrica(AApp);
            LOrdem := AApp.Producao.CriarOrdem(LFabrica.Acabado.Id, 3, Date).Valor;
            AApp.Producao.LiberarOrdem(LOrdem.Id);
            AApp.Producao.Apontar(LOrdem.Id, 10, 2, 0, 12, 'maria');

            LJson := LOrdem.ToJson;
            try
              LRestaurada := TOrdemProducao.Create;
              try
                LRestaurada.FromJson(LJson);
                TVerificar.Igual(LOrdem.Numero, LRestaurada.Numero, 'numero');
                TVerificar.Igual(1, LRestaurada.Componentes.Count, 'componentes');
                TVerificar.Igual(1, LRestaurada.Operacoes.Count, 'operacoes');
                TVerificar.Igual(1, LRestaurada.Apontamentos.Count, 'apontamentos');
                TVerificar.EhVerdade(LRestaurada.Status = opEmProducao, 'status');
              finally
                LRestaurada.Free;
              end;
            finally
              LJson.Free;
            end;
          end);
      end);

    LSuite.Teste('Custo medio movel pondera saldo antigo com a entrada nova',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LProduto: TProduto;
            LEsperado: Currency;
          begin
            LProduto := AApp.Produtos.Adicionar(CriarProduto('MP-X', 20, 10));
            LProduto.CustoMedio := 10;   // 10 unidades a 10 = 100

            AApp.Estoque.EntradaComCusto(LProduto.Id, 10, 20, 'compra');

            // (100 + 200) / 20 = 15
            LEsperado := 15;
            TVerificar.Igual(LEsperado, LProduto.CustoMedio, 'custo medio movel');
            TVerificar.Igual(20, LProduto.Estoque, 'saldo somado');
          end);
      end);

    LSuite.Teste('Dados de exemplo montam a fabrica completa',
      procedure
      begin
        ComApp(
          procedure(AApp: TAplicacao)
          var
            LMesa: TProduto;
            LExplosao: TArray<TLinhaExplosao>;
          begin
            TSeed.Popular(AApp);
            TVerificar.Igual(3, AApp.Centros.Contar, 'centros de trabalho');
            TVerificar.Igual(1, AApp.Ordens.Contar, 'uma ordem de exemplo');

            LMesa := AApp.Produtos.PorCodigo('MESA-120');
            TVerificar.NaoNulo(LMesa, 'produto acabado da fabrica');

            // 4 componentes diretos + 2 do tampo = 6 linhas na arvore
            LExplosao := AApp.Engenharia.Explodir(LMesa.Id, 1);
            TVerificar.Igual(6, Length(LExplosao), 'linhas da explosao');
            TVerificar.EhVerdade(
              AApp.Engenharia.CustoPadrao(LMesa.Id) > 0, 'custo padrao calculado');
          end);
      end);

    // ======================================================= FIREBIRD
    if AIncluirBanco then
      RegistrarTestesDeBanco(LSuite);

    Result := LSuite.Rodar;
  finally
    LSuite.Free;
  end;
end;

end.
