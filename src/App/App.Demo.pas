{*******************************************************************************
  App.Demo

  Roteiro automatico que exercita o sistema inteiro e vai narrando o que
  acontece. E a forma mais rapida de ver a arquitetura funcionando.

  Rode com:  GestaoComercial.exe --demo
*******************************************************************************}
unit App.Demo;

interface

procedure RodarDemonstracao;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Core.Types,
  Core.Events,
  Core.Validation,
  Domain.Entities,
  Domain.Enums,
  Domain.Events,
  Domain.Interfaces,
  Domain.Services,
  Domain.Producao,
  Domain.Producao.Services,
  Domain.Specifications,
  App.Bootstrap,
  App.Seed,
  App.Reports;

procedure Passo(const ANumero: Integer; const ATitulo: string);
begin
  Writeln;
  Writeln(StringOfChar('=', 76));
  Writeln(Format(' PASSO %d - %s', [ANumero, ATitulo]));
  Writeln(StringOfChar('=', 76));
end;

procedure Nota(const ATexto: string); overload;
begin
  Writeln('   ', ATexto);
end;

procedure Nota(const ATexto: string; const AArgs: array of const); overload;
begin
  Writeln('   ', Format(ATexto, AArgs));
end;

procedure Linhas(const A: TArray<string>);
var
  S: string;
begin
  for S in A do
    Writeln(S);
end;

procedure RodarDemonstracao;
var
  LApp: TAplicacao;
  LRelatorios: TRelatorios;
  LPedido: TPedido;
  LProduto: TProduto;
  LCliente: TCliente;
  LResultado: TResultado<Currency>;
  LPagamento: TResultado<string>;
  LEstoqueAntes: Integer;
  LArquivo: string;
  LEspec: ISpecification<TProduto>;
  // ---- PCP ----
  LMesa, LTampo, LChapa: TProduto;
  LOrdemRes: TResultado<TOrdemProducao>;
  LOrdem: TOrdemProducao;
  LLiberacao: TResultado<Currency>;
  LFecho: TResultado<TFechamentoOP>;
begin
  LApp := TAplicacao.Create(False);
  try
    LRelatorios := TRelatorios.Create(LApp);
    try
      // ------------------------------------------------------------------
      Passo(1, 'Container de dependencias montado');
      Nota('Servicos registrados (resolvidos sob demanda):');
      Linhas(LApp.Container.Registros);
      Nota('Repare: o dominio so conhece INTERFACES; as classes concretas');
      Nota('aparecem apenas em App.Bootstrap.');

      // ------------------------------------------------------------------
      Passo(2, 'Carga de dados de exemplo');
      TSeed.Popular(LApp);
      Linhas(LRelatorios.PainelGeral);

      // ------------------------------------------------------------------
      Passo(3, 'Validacao declarativa por atributos (RTTI)');
      Nota('Regras que o TCliente declara sem uma unica linha de "if":');
      Linhas(TValidador.DescreverRegras(TCliente));
      Nota('');
      Nota('Tentando cadastrar um cliente invalido...');
      LCliente := TCliente.Create;
      try
        LCliente.Nome := 'Jo';                 // curto demais
        LCliente.Documento := '123';           // nem CPF nem CNPJ
        LCliente.Email := 'sem-arroba';        // invalido
        LCliente.LimiteCredito := -50;         // negativo
        try
          LCliente.Validar;
        except
          on E: EValidacao do
          begin
            Nota('Rejeitado, com %d problema(s):', [Length(E.Erros)]);
            Linhas(E.Erros);
          end;
        end;
      finally
        LCliente.Free;
      end;

      // ------------------------------------------------------------------
      Passo(4, 'Specifications: filtros que se combinam');
      Nota('Produtos ativos E abaixo do minimo:');
      LEspec := TProdutoAtivo.Create.E(TProdutoAbaixoMinimo.Create);
      Nota('Regra montada: %s', [LEspec.Nome]);
      for LProduto in LApp.Produtos.Buscar(LEspec) do
        Nota(LProduto.Resumo);

      Nota('');
      Nota('Produtos caros (>= 1000) OU sem estoque, via metodo anonimo:');
      LEspec := TProdutoAcimaDe.Create(1000).Ou(
        TEspecDe<TProduto>.Nova(
          function(const AItem: TProduto): Boolean
          begin
            Result := AItem.EmFalta;
          end, 'sem estoque'));
      Nota('Regra montada: %s', [LEspec.Nome]);
      for LProduto in LApp.Produtos.Buscar(LEspec) do
        Nota(LProduto.Resumo);

      // ------------------------------------------------------------------
      Passo(5, 'Fluxo feliz: pedido -> confirmacao -> pagamento -> entrega');
      LPedido := LApp.Vendas.CriarPedido(3); // Distribuidora Norte (VIP)
      LApp.Vendas.AdicionarItem(LPedido.Id, 2, 6);   // 6 monitores (esvazia o estoque)
      LApp.Vendas.AdicionarItem(LPedido.Id, 7, 2);   // 2 cadeiras
      Nota('Pedido %s montado. Total bruto: %s',
        [LPedido.Numero, TFmt.Moeda(LPedido.TotalBruto)]);

      LResultado := LApp.Vendas.ConfirmarPedido(LPedido.Id);
      if LResultado.Sucesso then
      begin
        Nota('Confirmado! Total com desconto: %s', [TFmt.Moeda(LResultado.Valor)]);
        Nota('Desconto aplicado pela politica: %s',
          [TFmt.Moeda(LPedido.DescontoNegociado)]);
        Nota('Politica vigente: %s', [LApp.Politica.Nome]);
      end;

      LPagamento := LApp.Vendas.PagarPedido(LPedido.Id, fpPix);
      if LPagamento.Sucesso then
        Nota('Pago. Autorizacao: %s', [LPagamento.Valor]);

      LApp.Vendas.EnviarPedido(LPedido.Id);
      LApp.Vendas.EntregarPedido(LPedido.Id);
      Nota('Status final: %s', [StatusPedidoDescr(LPedido.Status)]);

      // ------------------------------------------------------------------
      Passo(6, 'Falha esperada 1: estoque insuficiente (TResultado, nao excecao)');
      LProduto := LApp.Produtos.PorCodigo('HUB-USBC');
      LEstoqueAntes := LProduto.Estoque;
      Nota('%s tem apenas %d em estoque.', [LProduto.Codigo, LEstoqueAntes]);

      LPedido := LApp.Vendas.CriarPedido(1);
      LApp.Vendas.AdicionarItem(LPedido.Id, LProduto.Id, 99);
      LResultado := LApp.Vendas.ConfirmarPedido(LPedido.Id);
      Nota('Sucesso? %s', [BoolToStr(LResultado.Sucesso, True)]);
      Nota('Motivo: %s', [LResultado.Erro]);
      Nota('Estoque continua em %d (nada foi movimentado).', [LProduto.Estoque]);

      // ------------------------------------------------------------------
      Passo(7, 'Falha esperada 2: limite de credito');
      LCliente := LApp.Clientes.PorId(5); // Padaria, limite baixo
      Nota('%s tem limite de %s e %s disponivel.',
        [LCliente.Nome, TFmt.Moeda(LCliente.LimiteCredito),
         TFmt.Moeda(LApp.Vendas.CreditoDisponivel(LCliente.Id))]);

      LPedido := LApp.Vendas.CriarPedido(LCliente.Id);
      LApp.Vendas.AdicionarItem(LPedido.Id, 1, 1); // notebook caro
      LResultado := LApp.Vendas.ConfirmarPedido(LPedido.Id);
      Nota('Motivo da recusa: %s', [LResultado.Erro]);
      Nota('(o evento TLimiteCreditoExcedido foi publicado - veja o passo 9)');

      // ------------------------------------------------------------------
      Passo(8, 'Cancelamento com devolucao de estoque (Unit of Work)');
      LPedido := LApp.Pedidos.PorId(2); // confirmado no seed
      LProduto := LApp.Produtos.PorId(LPedido.Itens[0].ProdutoId);
      Nota('Pedido %s (%s) reservou estoque. Saldo atual de %s: %d',
        [LPedido.Numero, StatusPedidoDescr(LPedido.Status),
         LProduto.Codigo, LProduto.Estoque]);

      LApp.Vendas.CancelarPedido(LPedido.Id, 'demonstracao');
      Nota('Apos o cancelamento, saldo de %s: %d',
        [LProduto.Codigo, LProduto.Estoque]);
      Nota('Status: %s', [StatusPedidoDescr(LPedido.Status)]);

      // ------------------------------------------------------------------
      Passo(9, 'Eventos de dominio publicados durante a demonstracao');
      Linhas(LApp.Mural);
      Nota('');
      Nota('Total de eventos: %d', [LApp.Eventos.TotalPublicados]);
      Nota('Nenhum servico chamou "enviar e-mail" ou "avisar compras"');
      Nota('diretamente: eles apenas anunciaram o que aconteceu.');

      // ------------------------------------------------------------------
      Passo(10, 'Relatorios');
      Linhas(LRelatorios.VendasPorStatus);
      Linhas(LRelatorios.TopProdutos(5));
      Linhas(LRelatorios.CurvaABC);
      Linhas(LRelatorios.PosicaoDeEstoque);

      // ------------------------------------------------------------------
      Passo(11, 'Persistencia em JSON (serializacao por RTTI)');
      LApp.Armazenamento.SalvarTudo;
      LArquivo := TPath.Combine(LApp.Armazenamento.Pasta, 'pedidos.json');
      Nota('Arquivos gravados em: %s', [LApp.Armazenamento.Pasta]);
      if TFile.Exists(LArquivo) then
      begin
        Nota('Inicio de pedidos.json:');
        Writeln(Copy(TFile.ReadAllText(LArquivo, TEncoding.UTF8), 1, 700));
        Writeln('   [...]');
      end;

      // ================================================================
      //                    MODULO INDUSTRIAL (PCP)
      // ================================================================
      Passo(12, 'Engenharia: estrutura de produto em dois niveis');
      LMesa := LApp.Produtos.PorCodigo('MESA-120');
      Nota('Item fabricado: %s', [LMesa.Descricao]);
      Nota('');
      Linhas(LRelatorios.EstruturaExplodida(LMesa.Id, 1));
      Nota('');
      Nota('Repare: a CHAPA-MDF nao aparece na receita direta da mesa.');
      Nota('Ela entra no segundo nivel, dentro do TAMPO-120. So a explosao');
      Nota('multinivel revela quanta chapa uma mesa realmente consome.');

      Passo(13, 'Engenharia: ficha de custo (roll-up material + transformacao)');
      Linhas(LRelatorios.FichaDeCusto(LMesa.Id));

      Passo(14, 'Engenharia recusa estrutura circular');
      Nota('Tentando fazer o TAMPO-120 levar a MESA-120 (que ja leva o tampo)...');
      LTampo := LApp.Produtos.PorCodigo('TAMPO-120');
      try
        LApp.Engenharia.DefinirComponente(LTampo.Id, LMesa.Id, 1);
        Nota('ERRO: a estrutura circular passou! Isso nao deveria acontecer.');
      except
        on E: EDominio do
        begin
          Nota('Recusado, como esperado:');
          Nota(E.Message);
          Nota('Sem essa checagem, a explosao entraria em recursao infinita.');
        end;
      end;

      Passo(15, 'MRP: necessidade de compra para produzir 50 mesas');
      Linhas(LRelatorios.NecessidadeDeMateriais(LMesa.Id, 50));

      Passo(16, 'Ordem de producao: criar, liberar e apontar');
      LOrdemRes := LApp.Producao.CriarOrdem(LMesa.Id, 5, Date + 5);
      if not LOrdemRes.Sucesso then
        Nota('Falha ao criar a ordem: %s', [LOrdemRes.Erro])
      else
      begin
        LOrdem := LOrdemRes.Valor;
        Nota('OP %s criada para 5 mesas. Custo previsto: %s',
          [LOrdem.Numero, TFmt.Moeda(LOrdem.CustoPrevisto)]);

        LChapa := LApp.Produtos.PorCodigo('PE-METAL');
        Nota('Estoque de %s antes da liberacao: %d',
          [LChapa.Codigo, LChapa.Estoque]);

        LLiberacao := LApp.Producao.LiberarOrdem(LOrdem.Id);
        if LLiberacao.Sucesso then
        begin
          Nota('Liberada. Material requisitado: %s',
            [TFmt.Moeda(LLiberacao.Valor)]);
          Nota('Estoque de %s depois: %d (a fabrica levou o material)',
            [LChapa.Codigo, LChapa.Estoque]);
        end
        else
          Nota('Liberacao recusada: %s', [LLiberacao.Erro]);

        Nota('');
        Nota('Apontando a operacao 10 (montagem): 5 boas em 70 minutos...');
        LApp.Producao.Apontar(LOrdem.Id, 10, 5, 0, 70, 'Carlos');

        Nota('Apontando a operacao 20 (embalagem): 4 boas, 1 refugo...');
        LApp.Producao.Apontar(LOrdem.Id, 20, 4, 1, 25, 'Marina',
          'caixa amassada no transporte');

        Nota('');
        Nota('Estoque de mesas acabadas agora: %d', [LMesa.Estoque]);
        Nota('(so a ULTIMA operacao do roteiro entrega produto ao estoque)');
      end;

      Passo(17, 'Fechamento da ordem: custo real x padrao');
      if LOrdemRes.Sucesso then
      begin
        LFecho := LApp.Producao.ConcluirOrdem(LOrdem.Id);
        if LFecho.Sucesso then
        begin
          Nota(LFecho.Valor.Resumo);
          Nota('');
          Nota('A entrada no estoque foi pelo custo PADRAO; a diferenca contra');
          Nota('o custo REAL virou variacao. E assim que a industria descobre');
          Nota('que a fabrica gastou mais (ou menos) do que a engenharia previu.');
        end
        else
          Nota('Nao foi possivel concluir: %s', [LFecho.Erro]);

        Nota('');
        Linhas(LRelatorios.DetalheDaOrdem(LOrdem.Id));
      end;

      Passo(18, 'Carga por centro de trabalho');
      Linhas(LRelatorios.CargaDeTrabalho);
      Linhas(LRelatorios.EficienciaDeProducao);

      Passo(19, 'Fim');
      Nota('Rode com --testes para ver a suite de testes (63 casos),');
      Nota('--db para usar o Firebird em vez de memoria,');
      Nota('ou sem parametros para abrir o menu interativo.');
    finally
      LRelatorios.Free;
    end;
  finally
    LApp.Free;
  end;
end;

end.
