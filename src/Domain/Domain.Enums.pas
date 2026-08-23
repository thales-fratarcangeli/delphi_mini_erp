{*******************************************************************************
  Domain.Enums

  Vocabulario do dominio: os estados e classificacoes do negocio.

  ESTUDO - conceitos demonstrados aqui:
    * Enumerados como forma de eliminar "numeros magicos" e strings soltas
    * MAQUINA DE ESTADOS: em vez de espalhar "if Status = ..." pelo sistema,
      centralizamos as transicoes validas numa unica funcao
    * Conjuntos (set of) para expressar grupos de estados
*******************************************************************************}
unit Domain.Enums;

interface

type
  TStatusPedido = (
    spRascunho,    // sendo montado, ainda nao reserva estoque
    spConfirmado,  // estoque reservado, aguardando pagamento
    spPago,        // pagamento aprovado
    spEnviado,     // saiu para entrega
    spEntregue,    // finalizado com sucesso
    spCancelado    // encerrado sem sucesso, estoque devolvido
  );
  TStatusPedidoSet = set of TStatusPedido;

  { Os dois ultimos sao movimentos de CHAO DE FABRICA:
      tmConsumo  -> baixa de componente requisitado por uma ordem de producao
      tmProducao -> entrada do produto acabado que a ordem gerou
    Separa-los de tmEntrada/tmSaida permite ler o extrato e saber, sem
    adivinhacao, o que foi compra/venda e o que foi fabricacao. }
  TTipoMovimento = (tmEntrada, tmSaida, tmAjuste, tmConsumo, tmProducao);

  /// Classificacao industrial do item. Define quem se compra e quem se fabrica.
  TTipoProduto = (
    tpMateriaPrima,    // comprado, entra na estrutura de outro item
    tpIntermediario,   // fabricado e consumido internamente (semiacabado)
    tpAcabado,         // fabricado e vendido
    tpConsumo,         // uso geral (nao entra na estrutura do produto)
    tpRevenda          // comprado e vendido sem transformacao
  );

  { Ciclo de vida da ordem de producao.
      Planejada  -> existe no papel, nao reservou nada
      Liberada   -> componentes requisitados/baixados, pode ir para a fabrica
      EmProducao -> ja houve pelo menos um apontamento
      Concluida  -> quantidade produzida entregue ao estoque
      Cancelada  -> encerrada; o que foi baixado volta ao estoque }
  TStatusOP = (
    opPlanejada,
    opLiberada,
    opEmProducao,
    opConcluida,
    opCancelada
  );
  TStatusOPSet = set of TStatusOP;

  TStatusOperacao = (soPendente, soEmExecucao, soConcluida);

  TCategoriaCliente = (ccComum, ccPrata, ccOuro, ccVip);

  TFormaPagamento = (fpDinheiro, fpPix, fpCartaoDebito, fpCartaoCredito, fpBoleto);

const
  /// Estados em que o pedido ainda "segura" estoque reservado.
  STATUS_COM_RESERVA: TStatusPedidoSet = [spConfirmado, spPago, spEnviado];
  /// Estados que ja consomem limite de credito do cliente.
  STATUS_EM_ABERTO: TStatusPedidoSet = [spConfirmado, spEnviado];
  /// Estados finais: nao admitem mais nenhuma transicao.
  STATUS_FINAIS: TStatusPedidoSet = [spEntregue, spCancelado];

  /// Ordens que ja consumiram material e ainda nao foram encerradas.
  OP_EM_ANDAMENTO: TStatusOPSet = [opLiberada, opEmProducao];
  /// Ordens que ainda ocupam capacidade no planejamento.
  OP_ABERTAS: TStatusOPSet = [opPlanejada, opLiberada, opEmProducao];
  OP_FINAIS: TStatusOPSet = [opConcluida, opCancelada];

  /// Itens que a fabrica produz (tem estrutura e roteiro).
  TIPOS_FABRICADOS = [tpIntermediario, tpAcabado];
  /// Itens que a fabrica compra.
  TIPOS_COMPRADOS = [tpMateriaPrima, tpConsumo, tpRevenda];

function StatusPedidoDescr(AStatus: TStatusPedido): string;
function TipoMovimentoDescr(ATipo: TTipoMovimento): string;
function TipoProdutoDescr(ATipo: TTipoProduto): string;
function StatusOPDescr(AStatus: TStatusOP): string;
function StatusOperacaoDescr(AStatus: TStatusOperacao): string;

/// Maquina de estados da ordem de producao (mesma ideia do pedido).
function TransicaoOPPermitida(ADe, APara: TStatusOP): Boolean;
function ProximosEstadosOP(ADe: TStatusOP): TStatusOPSet;
/// Movimento de estoque que aumenta o saldo?
function MovimentoEhEntrada(ATipo: TTipoMovimento): Boolean;
function CategoriaClienteDescr(ACategoria: TCategoriaCliente): string;
function FormaPagamentoDescr(AForma: TFormaPagamento): string;

/// Percentual de desconto concedido pela categoria do cliente (0..1).
function DescontoDaCategoria(ACategoria: TCategoriaCliente): Double;

/// Regra central da maquina de estados do pedido.
function TransicaoPermitida(ADe, APara: TStatusPedido): Boolean;
function ProximosEstados(ADe: TStatusPedido): TStatusPedidoSet;

implementation

function StatusPedidoDescr(AStatus: TStatusPedido): string;
begin
  case AStatus of
    spRascunho:   Result := 'Rascunho';
    spConfirmado: Result := 'Confirmado';
    spPago:       Result := 'Pago';
    spEnviado:    Result := 'Enviado';
    spEntregue:   Result := 'Entregue';
    spCancelado:  Result := 'Cancelado';
  else
    Result := '?';
  end;
end;

function TipoMovimentoDescr(ATipo: TTipoMovimento): string;
begin
  case ATipo of
    tmEntrada:  Result := 'Entrada';
    tmSaida:    Result := 'Saida';
    tmAjuste:   Result := 'Ajuste';
    tmConsumo:  Result := 'Consumo';
    tmProducao: Result := 'Producao';
  else
    Result := '?';
  end;
end;

function MovimentoEhEntrada(ATipo: TTipoMovimento): Boolean;
begin
  Result := ATipo in [tmEntrada, tmProducao];
end;

function TipoProdutoDescr(ATipo: TTipoProduto): string;
begin
  case ATipo of
    tpMateriaPrima:  Result := 'Materia-prima';
    tpIntermediario: Result := 'Semiacabado';
    tpAcabado:       Result := 'Produto acabado';
    tpConsumo:       Result := 'Consumo';
    tpRevenda:       Result := 'Revenda';
  else
    Result := '?';
  end;
end;

function StatusOPDescr(AStatus: TStatusOP): string;
begin
  case AStatus of
    opPlanejada:  Result := 'Planejada';
    opLiberada:   Result := 'Liberada';
    opEmProducao: Result := 'Em producao';
    opConcluida:  Result := 'Concluida';
    opCancelada:  Result := 'Cancelada';
  else
    Result := '?';
  end;
end;

function StatusOperacaoDescr(AStatus: TStatusOperacao): string;
begin
  case AStatus of
    soPendente:   Result := 'Pendente';
    soEmExecucao: Result := 'Em execucao';
    soConcluida:  Result := 'Concluida';
  else
    Result := '?';
  end;
end;

function ProximosEstadosOP(ADe: TStatusOP): TStatusOPSet;
begin
  case ADe of
    opPlanejada:  Result := [opLiberada, opCancelada];
    opLiberada:   Result := [opEmProducao, opCancelada];
    // Concluir direto e permitido: apontamento unico que fecha a ordem.
    opEmProducao: Result := [opConcluida, opCancelada];
  else
    Result := [];
  end;
end;

function TransicaoOPPermitida(ADe, APara: TStatusOP): Boolean;
begin
  Result := APara in ProximosEstadosOP(ADe);
end;

function CategoriaClienteDescr(ACategoria: TCategoriaCliente): string;
begin
  case ACategoria of
    ccComum: Result := 'Comum';
    ccPrata: Result := 'Prata';
    ccOuro:  Result := 'Ouro';
    ccVip:   Result := 'VIP';
  else
    Result := '?';
  end;
end;

function FormaPagamentoDescr(AForma: TFormaPagamento): string;
begin
  case AForma of
    fpDinheiro:      Result := 'Dinheiro';
    fpPix:           Result := 'PIX';
    fpCartaoDebito:  Result := 'Cartao de debito';
    fpCartaoCredito: Result := 'Cartao de credito';
    fpBoleto:        Result := 'Boleto';
  else
    Result := '?';
  end;
end;

function DescontoDaCategoria(ACategoria: TCategoriaCliente): Double;
begin
  case ACategoria of
    ccPrata: Result := 0.03;
    ccOuro:  Result := 0.06;
    ccVip:   Result := 0.10;
  else
    Result := 0.0;
  end;
end;

function ProximosEstados(ADe: TStatusPedido): TStatusPedidoSet;
begin
  case ADe of
    spRascunho:   Result := [spConfirmado, spCancelado];
    spConfirmado: Result := [spPago, spCancelado];
    spPago:       Result := [spEnviado, spCancelado];
    spEnviado:    Result := [spEntregue];
  else
    Result := []; // spEntregue e spCancelado sao finais
  end;
end;

function TransicaoPermitida(ADe, APara: TStatusPedido): Boolean;
begin
  Result := APara in ProximosEstados(ADe);
end;

end.
