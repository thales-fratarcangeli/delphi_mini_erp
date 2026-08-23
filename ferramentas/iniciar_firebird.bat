@echo off
REM ===========================================================================
REM  Sobe o servidor Firebird 5 desta maquina.
REM
REM  PRECISA SER EXECUTADO COMO ADMINISTRADOR.
REM  Motivo: o Firebird abre a base de seguranca (security5.fdb) e os arquivos
REM  de lock dentro de "C:\Program Files\...", onde um usuario comum nao tem
REM  permissao de escrita. Sem isso a conexao falha com:
REM      "Your user name and password are not defined"
REM
REM  Clique com o botao direito neste arquivo -> "Executar como administrador".
REM ===========================================================================

set FBDIR=C:\Program Files\Firebird\Firebird_5_0

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo [ERRO] Este script precisa ser executado COMO ADMINISTRADOR.
  echo        Botao direito neste arquivo -^> Executar como administrador.
  echo.
  pause
  exit /b 1
)

echo.
echo === Opcao 1: instalar como SERVICO do Windows (recomendado) ===
echo Sobe junto com o Windows e nao precisa desta janela aberta.
echo.
echo === Opcao 2: rodar como aplicacao ===
echo Fica ativo so enquanto o processo existir.
echo.
choice /c 12S /n /m "Escolha [1=servico, 2=aplicacao, S=sair]: "

if errorlevel 3 exit /b 0
if errorlevel 2 goto aplicacao
if errorlevel 1 goto servico

:servico
echo.
echo Instalando o servico...
"%FBDIR%\instsvc.exe" install
"%FBDIR%\instsvc.exe" start
echo.
echo Servico instalado e iniciado. Confira com: sc query FirebirdServerDefaultInstance
goto fim

:aplicacao
echo.
echo Subindo o Firebird como aplicacao (feche esta janela para parar)...
"%FBDIR%\firebird.exe" -a
goto fim

:fim
echo.
echo Para conferir se a porta 3050 esta ouvindo:
echo    powershell -c "(Test-NetConnection 127.0.0.1 -Port 3050).TcpTestSucceeded"
echo.
pause
