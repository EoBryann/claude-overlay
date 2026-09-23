<#
  Claude Overlay - janela sempre no topo com as sessões do Claude Code (perfis Empresa e Pessoal).
  Uso:  powershell -STA -File overlay.ps1               janela
        powershell -File overlay.ps1 -Diagnostico       imprime as sessões e sai
        powershell -File overlay.ps1 -TestarToast       dispara um toast e sai
#>
param([switch]$Diagnostico, [switch]$TestarToast)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:Base    = Join-Path $env:USERPROFILE '.claude-overlay'
$script:LogPath = Join-Path $script:Base 'overlay.log'
$script:PosPath = Join-Path $script:Base 'overlay.pos.json'
$script:Perfis  = @(
  [pscustomobject]@{ Nome = 'Empresa'; Chave = 'empresa'; Cfg = (Join-Path $env:USERPROFILE '.claude-empresa') },
  [pscustomobject]@{ Nome = 'Pessoal'; Chave = 'pessoal'; Cfg = (Join-Path $env:USERPROFILE '.claude') }
)
$script:Estados = @{
  permission  = @{ Rotulo = 'pede permissão'; Peso = 0 }
  needs_input = @{ Rotulo = 'esperando você'; Peso = 1 }
  done        = @{ Rotulo = 'respondeu';      Peso = 2 }
  working     = @{ Rotulo = 'trabalhando';    Peso = 3 }
  idle        = @{ Rotulo = 'ociosa';         Peso = 4 }
  ended       = @{ Rotulo = 'encerrada';      Peso = 5 }
  unknown     = @{ Rotulo = 'sem sinal';      Peso = 6 }
}
# cores de estado (tema escuro fixo)
$script:CoresEscuro = @{ permission = '#FFFFB020'; needs_input = '#FFFFB020'; done = '#FF3DDC84'; working = '#FF4FA3FF'; idle = '#FF7B8594'; ended = '#FF7B8594'; unknown = '#FF5B6472' }
$script:Alerta = @('done', 'permission', 'needs_input')
$script:ToastOk = $false
try {
  $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $script:ToastOk = $true
} catch { }

function Log([string]$m) {
  try {
    if ((Test-Path -LiteralPath $script:LogPath) -and (Get-Item -LiteralPath $script:LogPath).Length -gt 1MB) { Clear-Content -LiteralPath $script:LogPath }
    Add-Content -LiteralPath $script:LogPath -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
  } catch { }
}
function Read-Json([string]$path) {
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function AgoraMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Tempo-Atras([int64]$ms) {
  if ($ms -le 0) { return '' }
  $s = [int](((AgoraMs) - $ms) / 1000)
  if ($s -lt 0) { $s = 0 }
  if ($s -lt 60) { return "há ${s}s" }
  $m = [int][math]::Floor($s / 60)
  if ($m -lt 60) { return "há ${m}min" }
  $h = [int][math]::Floor($m / 60)
  if ($h -lt 24) { return "há ${h}h" }
  return ("há {0}d" -f [int][math]::Floor($h / 24))
}

# ---- nome do chat ----
# O Claude grava o titulo no transcript (custom-title quando renomeado, ai-title quando automatico) e
# repete a linha a cada poucas mensagens, entao basta ler o fim do arquivo. Cache por sessao para
# nao reler transcripts de varios MB a cada tick; o arquivo e aberto compartilhado para nao travar o Claude.
$script:Titulos = @{}
$script:RxCustom = [regex]'"customTitle":"((?:[^"\\]|\\.)*)"'
$script:RxAi     = [regex]'"aiTitle":"((?:[^"\\]|\\.)*)"'
function Ler-Cauda([string]$path, [int64]$bytes) {
  $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
  try {
    $ini = [math]::Max([int64]0, $fs.Length - $bytes)
    $null = $fs.Seek($ini, [IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] ([int]($fs.Length - $ini))
    $lidos = 0
    while ($lidos -lt $buf.Length) { $n = $fs.Read($buf, $lidos, $buf.Length - $lidos); if ($n -le 0) { break }; $lidos += $n }
    return @{ Texto = [Text.Encoding]::UTF8.GetString($buf, 0, $lidos); Inteiro = ($ini -eq 0) }
  } finally { $fs.Dispose() }
}
function Ultimo-Titulo([regex]$rx, [string]$texto) {
  $ms = $rx.Matches($texto)
  if ($ms.Count -eq 0) { return $null }
  $v = $ms[$ms.Count - 1].Groups[1].Value
  try { return [regex]::Unescape($v) } catch { return $v }
}
function Titulo-Sessao($perfil, [string]$sid, [string]$transcript, [int64]$em) {
  $agora = AgoraMs
  $c = $script:Titulos[$sid]
  if ($c) {
    $idade = $agora - $c.Lido
    if ($idade -lt 15000 -or ($idade -lt 60000 -and $c.Em -eq $em)) { return $c.Titulo }
  } else {
    $c = @{ Custom = $null; Ai = $null; Titulo = ''; Caminho = ''; Lido = 0; Em = 0 }
    $script:Titulos[$sid] = $c
  }
  $c.Lido = $agora; $c.Em = $em
  try {
    if (-not $c.Caminho) {
      if ($transcript -and (Test-Path -LiteralPath $transcript)) { $c.Caminho = $transcript }
      else {
        $f = @(Get-ChildItem -Path (Join-Path $perfil.Cfg ('projects\*\' + $sid + '.jsonl')) -File -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($f) { $c.Caminho = $f.FullName }
      }
    }
    if (-not $c.Caminho) { return $c.Titulo }
    $primeira = (-not $c.Custom) -and (-not $c.Ai)
    $cauda = Ler-Cauda $c.Caminho 262144
    $cu = Ultimo-Titulo $script:RxCustom $cauda.Texto
    $ai = Ultimo-Titulo $script:RxAi $cauda.Texto
    if ($primeira -and -not $cu -and -not $ai -and -not $cauda.Inteiro) {
      $cauda = Ler-Cauda $c.Caminho 4194304
      $cu = Ultimo-Titulo $script:RxCustom $cauda.Texto
      $ai = Ultimo-Titulo $script:RxAi $cauda.Texto
    }
    if ($cu) { $c.Custom = $cu }
    if ($ai) { $c.Ai = $ai }
    if ($c.Custom) { $c.Titulo = $c.Custom } elseif ($c.Ai) { $c.Titulo = $c.Ai }
  } catch { Log ('Titulo-Sessao: ' + $_.Exception.Message) }
  return $c.Titulo
}

function Get-Sessoes {
  $vivos = @{}
  foreach ($p in @(Get-Process -Name claude, node -ErrorAction SilentlyContinue)) { $vivos[[int]$p.Id] = $true }
  $lista = New-Object System.Collections.ArrayList
  foreach ($perfil in $script:Perfis) {
    $regDir = Join-Path $perfil.Cfg 'sessions'
    $stDir  = Join-Path $script:Base ('state\' + $perfil.Chave)
    $estados = @{}
    if (Test-Path -LiteralPath $stDir) {
      foreach ($f in @(Get-ChildItem -LiteralPath $stDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $j = Read-Json $f.FullName
        if ($j -and $j.sessionId) { $estados[[string]$j.sessionId] = $j }
      }
    }
    if (-not (Test-Path -LiteralPath $regDir)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $regDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
      $r = Read-Json $f.FullName
      if (-not $r -or -not $r.pid -or -not $r.sessionId) { continue }
      if (-not $vivos.ContainsKey([int]$r.pid)) { continue }
      $st = $estados[[string]$r.sessionId]
      $estado = 'unknown'; $detalhe = 'sem sinal ainda (hooks entram no próximo evento da sessão)'; $em = [int64]$r.startedAt; $subs = 0; $transcript = ''
      if ($st) {
        if ($st.transcript) { $transcript = [string]$st.transcript }
        if ($st.state)     { $estado  = [string]$st.state }
        if ($st.detail)    { $detalhe = [string]$st.detail }
        if ($st.at)        { $em      = [int64]$st.at }
        if ($st.subagents) { $subs    = [int]$st.subagents }
      }
      if (-not $script:Estados.ContainsKey($estado)) { $estado = 'unknown' }
      $pasta = ''
      if ($r.cwd) { $pasta = Split-Path -Leaf ([string]$r.cwd) }
      $titulo = Titulo-Sessao $perfil ([string]$r.sessionId) $transcript $em
      [void]$lista.Add([pscustomobject]@{
        Perfil = $perfil.Nome; Chave = $perfil.Chave; SessionId = [string]$r.sessionId; ProcId = [int]$r.pid
        Nome = [string]$r.name; Titulo = $titulo; Pasta = $pasta; Cwd = [string]$r.cwd; Estado = $estado; Detalhe = $detalhe
        Em = $em; Subagentes = $subs; Peso = [int]$script:Estados[$estado].Peso
      })
    }
  }
  return @($lista | Sort-Object -Property @{Expression = 'Perfil'}, @{Expression = 'Peso'}, @{Expression = 'Em'; Descending = $true})
}

function Show-Toast([string]$titulo, [string]$texto) {
  if (-not $script:ToastOk) { try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }; return }
  try {
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $t1 = [System.Security.SecurityElement]::Escape($titulo)
    $t2 = [System.Security.SecurityElement]::Escape($texto)
    $xml = "<toast duration='short'><visual><binding template='ToastGeneric'><text>$t1</text><text>$t2</text><text placement='attribution'>Claude Overlay</text></binding></visual><audio src='ms-winsoundevent:Notification.Default'/></toast>"
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification -ArgumentList $doc
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
  } catch {
    Log ("toast falhou: " + $_.Exception.Message)
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
  }
}

if ($Diagnostico) {
  $s = Get-Sessoes
  if ($s.Count -eq 0) { 'Nenhuma sessão viva encontrada.'; exit }
  $s | Format-Table Perfil, Nome, Titulo, Pasta, Estado, Subagentes, @{n = 'Quando'; e = { Tempo-Atras $_.Em }}, Detalhe -AutoSize | Out-String -Width 220
  exit
}
if ($TestarToast) {
  Show-Toast 'Meu chat respondeu' '[Pessoal · meu-projeto] Teste: se você está lendo isto, o toast funciona.'
  Start-Sleep -Seconds 1
  'toast enviado (ToastOk=' + $script:ToastOk + ')'
  exit
}

# ---- uma instância só ----
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeOverlay')
if (-not $script:Mutex.WaitOne(0, $false)) { Log 'já existe uma instância aberta; saindo'; exit }

# ---- janela ----
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Overlay" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="CanResizeWithGrip"
        Width="460" Height="340" MinWidth="320" MinHeight="120"
        FontFamily="Segoe UI" FontSize="12" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#FF9AA4B2"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="7,1"/>
      <Setter Property="Margin" Value="2,0,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#33808080"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Name="Shell" CornerRadius="10" Background="#F2141821" BorderBrush="#40FFFFFF" BorderThickness="1">
    <Grid>
      <DockPanel Name="Painel" LastChildFill="True">
        <Border Name="TitleBar" DockPanel.Dock="Top" Background="#FF1B2431" CornerRadius="10,10,0,0" Padding="10,6,6,6">
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
              <Slider Name="Brilho" Minimum="0" Maximum="1" Value="1" Width="72" Height="18" VerticalAlignment="Center" Margin="0,0,8,0"
                      IsMoveToPointEnabled="True" Background="Transparent" ToolTip="Brilho do conteúdo: abaixe para escurecer e embaçar a lista, e ninguém lê por cima do seu ombro (a roda do mouse sobre a barra também ajusta)"/>
              <Button Name="BtnSom" Content="som" ToolTip="Silenciar / ativar toasts"/>
              <Button Name="BtnCompacto" Content="&#x25BE;" ToolTip="Só a barra de resumo"/>
              <Button Name="BtnMini" Content="&#x25A1;" ToolTip="Encolher num quadradinho (clique nele para voltar)"/>
              <Button Name="BtnFechar" Content="&#x2715;" ToolTip="Fechar"/>
            </StackPanel>
            <TextBlock Name="Titulo" Text="Claude" Foreground="#FFEDEFF3" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <TextBlock Name="Resumo" Foreground="#FF9AA4B2" Margin="10,0,0,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
          </DockPanel>
        </Border>
        <Grid Name="Conteudo">
          <ScrollViewer Name="Scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="6,4,6,6">
            <StackPanel Name="Lista"/>
          </ScrollViewer>
          <Border Name="Escurecedor" Background="#FF06080C" CornerRadius="0,0,10,10" Opacity="0" IsHitTestVisible="False"/>
        </Grid>
      </DockPanel>
      <Grid Name="MiniPanel" Visibility="Collapsed" Background="Transparent" Cursor="Hand" ToolTip="Claude Overlay">
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
          <StackPanel Orientation="Horizontal" Margin="0,1">
            <Ellipse Name="MiniDotTrab" Width="8" Height="8" Margin="0,0,6,0" VerticalAlignment="Center" Fill="#FF4FA3FF"/>
            <TextBlock Name="MiniTrab" Text="0" FontSize="12" FontWeight="SemiBold" Foreground="#FFEDEFF3" MinWidth="14"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,1">
            <Ellipse Name="MiniDotEsp" Width="8" Height="8" Margin="0,0,6,0" VerticalAlignment="Center" Fill="#FFFFB020"/>
            <TextBlock Name="MiniEsp" Text="0" FontSize="12" FontWeight="SemiBold" Foreground="#FFEDEFF3" MinWidth="14"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,1">
            <Ellipse Name="MiniDotResp" Width="8" Height="8" Margin="0,0,6,0" VerticalAlignment="Center" Fill="#FF3DDC84"/>
            <TextBlock Name="MiniResp" Text="0" FontSize="12" FontWeight="SemiBold" Foreground="#FFEDEFF3" MinWidth="14"/>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:Win = [Windows.Markup.XamlReader]::Load($reader)
$script:Shell       = $script:Win.FindName('Shell')
$script:TitleBar    = $script:Win.FindName('TitleBar')
$script:Titulo      = $script:Win.FindName('Titulo')
$script:Lista       = $script:Win.FindName('Lista')
$script:Scroll      = $script:Win.FindName('Scroll')
$script:Resumo      = $script:Win.FindName('Resumo')
$script:BtnSom      = $script:Win.FindName('BtnSom')
$script:BtnCompacto = $script:Win.FindName('BtnCompacto')
$script:BtnFechar   = $script:Win.FindName('BtnFechar')
$script:BtnMini     = $script:Win.FindName('BtnMini')
$script:Brilho      = $script:Win.FindName('Brilho')
$script:Conteudo    = $script:Win.FindName('Conteudo')
$script:Escurecedor = $script:Win.FindName('Escurecedor')
$script:Painel      = $script:Win.FindName('Painel')
$script:MiniPanel   = $script:Win.FindName('MiniPanel')
$script:MiniTrab    = $script:Win.FindName('MiniTrab')
$script:MiniEsp     = $script:Win.FindName('MiniEsp')
$script:MiniResp    = $script:Win.FindName('MiniResp')
$script:MiniDotTrab = $script:Win.FindName('MiniDotTrab')
$script:MiniDotEsp  = $script:Win.FindName('MiniDotEsp')
$script:MiniDotResp = $script:Win.FindName('MiniDotResp')

$script:BrushConv = New-Object Windows.Media.BrushConverter
$script:Brushes = @{}
function Brush([string]$hex) {
  if (-not $script:Brushes.ContainsKey($hex)) {
    $b = $script:BrushConv.ConvertFromString($hex)
    $b.Freeze()
    $script:Brushes[$hex] = $b
  }
  return $script:Brushes[$hex]
}
function Thick([double]$l, [double]$t, [double]$r, [double]$b) { return New-Object Windows.Thickness -ArgumentList $l, $t, $r, $b }
$script:GridLen = New-Object Windows.GridLengthConverter

$script:Prev = @{}
$script:Ack = @{}
$script:Iniciado = $false
$script:Mudo = $false
$script:Compacto = $false
$script:Moveu = $false
$script:AlturaCheia = 340
$script:LarguraCheia = 460
$script:Mini = $false
$script:TamanhoMini = 66
$script:Tick = 0
$script:BrilhoValor = 1.0
$script:Assinatura = ''
$script:Tema = $null

# ---- tema / brilho ----
function Mix([string]$a, [string]$b, [double]$t) {
  $ca = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($a)
  $cb = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($b)
  $r  = [int][math]::Round([double]$ca.R + ([double]$cb.R - [double]$ca.R) * $t)
  $g  = [int][math]::Round([double]$ca.G + ([double]$cb.G - [double]$ca.G) * $t)
  $bl = [int][math]::Round([double]$ca.B + ([double]$cb.B - [double]$ca.B) * $t)
  return ('{0:X2}{1:X2}{2:X2}' -f $r, $g, $bl)
}
function Calcular-Tema([double]$v) {
  # tema escuro fixo; o brilho nao muda cores, ele escurece e embaca o conteudo (ver Aplicar-Brilho)
  return @{
    Fundo = '#F2141821'; Barra = '#FF1B2431'; Borda = '#40FFFFFF'
    Texto1 = '#FFEDEFF3'; Texto2 = '#FF9AA4B2'; Texto3 = '#FF6B7685'; Linha = '#12FFFFFF'
    Cores = $script:CoresEscuro
  }
}
function Atualizar-BotaoSom {
  if ($script:Mudo) { $script:BtnSom.Content = 'mudo'; $script:BtnSom.Foreground = Brush $script:Tema.Cores.permission }
  else { $script:BtnSom.Content = 'som'; $script:BtnSom.Foreground = Brush $script:Tema.Texto2 }
}
function Aplicar-Brilho([double]$v) {
  if ($v -lt 0) { $v = 0 }
  if ($v -gt 1) { $v = 1 }
  $script:BrilhoValor = $v
  $script:Tema = Calcular-Tema $v
  $script:Shell.Background      = Brush $script:Tema.Fundo
  $script:Shell.BorderBrush     = Brush $script:Tema.Borda
  $script:TitleBar.Background   = Brush $script:Tema.Barra
  $script:Titulo.Foreground     = Brush $script:Tema.Texto1
  $script:Resumo.Foreground     = Brush $script:Tema.Texto2
  $script:BtnCompacto.Foreground = Brush $script:Tema.Texto2
  $script:BtnMini.Foreground    = Brush $script:Tema.Texto2
  $script:BtnFechar.Foreground  = Brush $script:Tema.Texto2
  $script:MiniDotTrab.Fill = Brush $script:Tema.Cores.working
  $script:MiniDotEsp.Fill  = Brush $script:Tema.Cores.permission
  $script:MiniDotResp.Fill = Brush $script:Tema.Cores.done
  foreach ($tb in @($script:MiniTrab, $script:MiniEsp, $script:MiniResp)) { $tb.Foreground = Brush $script:Tema.Texto1 }
  Atualizar-BotaoSom
  # escurecedor de privacidade: em 1 nada muda; conforme baixa, uma camada escura cobre a lista
  # e, abaixo de 0,5, ela tambem fica embacada, para ninguem ler por cima do ombro
  $script:Escurecedor.Opacity = (1 - $v) * 0.92
  if ($v -lt 0.5) {
    $ef = New-Object Windows.Media.Effects.BlurEffect
    $ef.Radius = (0.5 - $v) * 9
    $script:Lista.Effect = $ef
  } else {
    $script:Lista.Effect = $null
  }
  if ([math]::Abs($script:Brilho.Value - $v) -gt 0.001) { $script:Brilho.Value = $v }
}

function New-Cabecalho([string]$nome, [int]$qtd) {
  $tb = New-Object Windows.Controls.TextBlock
  $tb.Text = ($nome.ToUpper() + '  ' + $qtd)
  $tb.Foreground = Brush $script:Tema.Texto3
  $tb.FontSize = 10.5
  $tb.FontWeight = [Windows.FontWeights]::SemiBold
  $tb.Margin = Thick 4 6 0 2
  return $tb
}

function New-Linha($s, [bool]$pendente) {
  $cfg = $script:Estados[$s.Estado]
  $cor = [string]$script:Tema.Cores[$s.Estado]
  $b = New-Object Windows.Controls.Border
  $b.CornerRadius = New-Object Windows.CornerRadius -ArgumentList 6
  $b.Padding = Thick 8 5 8 5
  $b.Margin = Thick 0 2 0 2
  $b.Cursor = [Windows.Input.Cursors]::Hand
  $b.Tag = ($s.SessionId + '|' + $s.Em)
  $dica = $s.Perfil + ' · ' + $s.Cwd + "`nPID " + $s.ProcId
  if ($s.Titulo) { $dica += "`nChat: " + $s.Titulo }
  $b.ToolTip = ($dica + "`n" + $s.Detalhe)
  if ($pendente) {
    $b.Background = Brush ($cor -replace '^#FF', '#2E')
    $b.BorderBrush = Brush $cor
    $b.BorderThickness = Thick 1 1 1 1
  } else {
    $b.Background = Brush $script:Tema.Linha
    $b.BorderThickness = Thick 0 0 0 0
  }
  $b.Add_MouseLeftButtonUp({
    param($sender, $e)
    $partes = ([string]$sender.Tag).Split('|')
    $script:Ack[$partes[0]] = [int64]$partes[1]
    Atualizar
  })

  $g = New-Object Windows.Controls.Grid
  foreach ($w in @('Auto', '*', 'Auto')) {
    $c = New-Object Windows.Controls.ColumnDefinition
    $c.Width = $script:GridLen.ConvertFromString($w)
    $g.ColumnDefinitions.Add($c)
  }
  $dot = New-Object Windows.Shapes.Ellipse
  $dot.Width = 9; $dot.Height = 9
  $dot.Fill = Brush $cor
  $dot.Margin = Thick 0 4 8 0
  $dot.VerticalAlignment = [Windows.VerticalAlignment]::Top
  [Windows.Controls.Grid]::SetColumn($dot, 0)
  [void]$g.Children.Add($dot)

  $sp = New-Object Windows.Controls.StackPanel
  $l1 = New-Object Windows.Controls.TextBlock
  $l1.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
  $r1 = New-Object Windows.Documents.Run -ArgumentList ([string]$s.Nome)
  $r1.FontWeight = [Windows.FontWeights]::SemiBold
  $r1.Foreground = Brush $script:Tema.Texto1
  $r2 = New-Object Windows.Documents.Run -ArgumentList ('  ' + $s.Pasta)
  $r2.Foreground = Brush $script:Tema.Texto3
  [void]$l1.Inlines.Add($r1); [void]$l1.Inlines.Add($r2)
  if ($s.Subagentes -gt 0) {
    $r3 = New-Object Windows.Documents.Run -ArgumentList ('  ' + $s.Subagentes + ' sub')
    $r3.Foreground = Brush $script:Tema.Cores.working
    [void]$l1.Inlines.Add($r3)
  }
  $l2 = New-Object Windows.Controls.TextBlock
  $l2.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
  $l2.Margin = Thick 0 1 0 0
  $r4 = New-Object Windows.Documents.Run -ArgumentList ([string]$cfg.Rotulo)
  $r4.Foreground = Brush $cor
  # a linha de baixo mostra o nome do chat; a resposta/ferramenta fica no tooltip (sem nome ainda, cai no detalhe)
  $linha2 = $s.Detalhe
  if ($s.Titulo) { $linha2 = $s.Titulo }
  $r5 = New-Object Windows.Documents.Run -ArgumentList (' · ' + $linha2)
  $r5.Foreground = Brush $script:Tema.Texto2
  [void]$l2.Inlines.Add($r4); [void]$l2.Inlines.Add($r5)
  [void]$sp.Children.Add($l1); [void]$sp.Children.Add($l2)
  [Windows.Controls.Grid]::SetColumn($sp, 1)
  [void]$g.Children.Add($sp)

  $t = New-Object Windows.Controls.TextBlock
  $t.Text = (Tempo-Atras $s.Em)
  $t.Foreground = Brush $script:Tema.Texto3
  $t.FontSize = 11
  $t.Margin = Thick 8 0 0 0
  $t.VerticalAlignment = [Windows.VerticalAlignment]::Top
  [Windows.Controls.Grid]::SetColumn($t, 2)
  [void]$g.Children.Add($t)

  $b.Child = $g
  return $b
}

function Notificar($s) {
  if ($script:Mudo) { return }
  $rotulo = [string]$script:Estados[$s.Estado].Rotulo
  $quem = $s.Nome
  if ($s.Titulo) { $quem = $s.Titulo }
  Show-Toast ($quem + ' ' + $rotulo) ('[' + $s.Perfil + ' · ' + $s.Pasta + '] ' + $s.Detalhe)
}

function Atualizar {
  try {
    $sessoes = Get-Sessoes
    $agora = AgoraMs
    foreach ($s in $sessoes) {
      $chave = ($s.Estado + '|' + $s.Em)
      $antes = $script:Prev[$s.SessionId]
      if ($script:Iniciado -and $antes -ne $chave -and ($script:Alerta -contains $s.Estado) -and (($agora - $s.Em) -lt 120000)) {
        Notificar $s
      }
      $script:Prev[$s.SessionId] = $chave
    }
    $script:Iniciado = $true

    # so redesenha a lista quando algo mudou (ou a cada 4 ticks, para atualizar o "há Xs")
    $assin = (@($sessoes | ForEach-Object { $_.SessionId + '|' + $_.Estado + '|' + $_.Em + '|' + $_.Subagentes + '|' + $_.Titulo + '|' + $_.Detalhe }) -join ';') +
             '#' + (@($script:Ack.Keys | ForEach-Object { $_ + '=' + $script:Ack[$_] }) -join ',')
    if ($assin -ne $script:Assinatura -or (($script:Tick % 4) -eq 0)) {
      $script:Assinatura = $assin
      $script:Lista.Children.Clear()
      if ($sessoes.Count -eq 0) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = 'Nenhuma sessão do Claude aberta.'
        $tb.Foreground = Brush $script:Tema.Texto3
        $tb.Margin = Thick 6 10 0 0
        [void]$script:Lista.Children.Add($tb)
      }
      $perfilAtual = ''
      foreach ($s in $sessoes) {
        if ($s.Perfil -ne $perfilAtual) {
          $perfilAtual = $s.Perfil
          $qtd = @($sessoes | Where-Object { $_.Perfil -eq $perfilAtual }).Count
          [void]$script:Lista.Children.Add((New-Cabecalho $perfilAtual $qtd))
        }
        $ack = [int64]0
        if ($script:Ack.ContainsKey($s.SessionId)) { $ack = [int64]$script:Ack[$s.SessionId] }
        $pendente = ($script:Alerta -contains $s.Estado) -and ($s.Em -gt $ack)
        [void]$script:Lista.Children.Add((New-Linha $s $pendente))
      }
    }
    $trab = @($sessoes | Where-Object { $_.Estado -eq 'working' }).Count
    $esp  = @($sessoes | Where-Object { $_.Estado -eq 'permission' -or $_.Estado -eq 'needs_input' }).Count
    $resp = @($sessoes | Where-Object { $_.Estado -eq 'done' }).Count
    $script:Resumo.Text = "$trab trabalhando · $esp esperando · $resp respondeu"
    $script:Win.Title = "Claude Overlay · $trab/$esp/$resp"
    $script:MiniTrab.Text = [string]$trab
    $script:MiniEsp.Text  = [string]$esp
    $script:MiniResp.Text = [string]$resp
    $script:MiniPanel.ToolTip = ($script:Resumo.Text + "`nClique para abrir, arraste para mover")

    # no quadradinho, a borda acende quando ha algo nao visto (ambar se alguem espera voce, verde se so respondeu)
    $corBorda = $script:Tema.Borda; $espBorda = 1.0
    if ($script:Mini) {
      $pend = @($sessoes | Where-Object { ($script:Alerta -contains $_.Estado) -and (-not $script:Ack.ContainsKey($_.SessionId) -or $_.Em -gt [int64]$script:Ack[$_.SessionId]) })
      if ($pend.Count -gt 0) {
        $espBorda = 2.0
        if (@($pend | Where-Object { $_.Estado -ne 'done' }).Count -gt 0) { $corBorda = $script:Tema.Cores.permission } else { $corBorda = $script:Tema.Cores.done }
      }
    }
    $script:Shell.BorderBrush = Brush $corBorda
    $script:Shell.BorderThickness = Thick $espBorda $espBorda $espBorda $espBorda

    $script:Tick++
    if (($script:Tick % 8) -eq 0) { $script:Win.Topmost = $false; $script:Win.Topmost = $true }
  } catch {
    Log ('Atualizar: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
  }
}

function Salvar-Posicao {
  try {
    $alt = $script:Win.Height
    if ($script:Compacto -or $script:Mini) { $alt = $script:AlturaCheia }
    $larg = $script:Win.Width
    if ($script:Mini) { $larg = $script:LarguraCheia }
    @{ Left = $script:Win.Left; Top = $script:Win.Top; Width = $larg; Height = $alt; Compacto = $script:Compacto; Mini = $script:Mini; Mudo = $script:Mudo; Brilho = $script:BrilhoValor } |
      ConvertTo-Json | Set-Content -LiteralPath $script:PosPath -Encoding UTF8
  } catch { Log ('Salvar-Posicao: ' + $_.Exception.Message) }
}
function Carregar-Posicao {
  $wa = [Windows.SystemParameters]::WorkArea
  $script:Win.Left = $wa.Right - $script:Win.Width - 12
  $script:Win.Top = 60
  $p = Read-Json $script:PosPath
  if (-not $p) { return }
  try {
    $vs = [Windows.SystemParameters]::VirtualScreenWidth; $vh = [Windows.SystemParameters]::VirtualScreenHeight
    $vl = [Windows.SystemParameters]::VirtualScreenLeft; $vt = [Windows.SystemParameters]::VirtualScreenTop
    if ($p.Width -ge 320) { $script:Win.Width = [double]$p.Width }
    if ($p.Height -ge 120) { $script:AlturaCheia = [double]$p.Height; $script:Win.Height = [double]$p.Height }
    if ($p.Left -ge ($vl - 50) -and $p.Left -lt ($vl + $vs - 100)) { $script:Win.Left = [double]$p.Left }
    if ($p.Top -ge ($vt - 10) -and $p.Top -lt ($vt + $vh - 60)) { $script:Win.Top = [double]$p.Top }
    if ($p.Mudo) { $script:Mudo = $true }
    if ($null -ne $p.Brilho) { Aplicar-Brilho ([double]$p.Brilho) }
    if ($p.Compacto) { $script:Compacto = $false; Alternar-Compacto }
    if ($p.Mini) { Entrar-Mini }
  } catch { Log ('Carregar-Posicao: ' + $_.Exception.Message) }
}
function Alternar-Compacto {
  $script:Compacto = -not $script:Compacto
  if ($script:Compacto) {
    $script:AlturaCheia = $script:Win.Height
    $script:Conteudo.Visibility = [Windows.Visibility]::Collapsed
    $script:Win.ResizeMode = [Windows.ResizeMode]::NoResize
    $script:Win.MinHeight = 0
    $alturaTitulo = $script:TitleBar.ActualHeight
    if ($alturaTitulo -lt 20) { $alturaTitulo = 30 }
    $script:Win.Height = $alturaTitulo + 2
    $script:BtnCompacto.Content = [string][char]0x25B4
  } else {
    $script:Win.MinHeight = 120
    $script:Win.Height = $script:AlturaCheia
    $script:Conteudo.Visibility = [Windows.Visibility]::Visible
    $script:Win.ResizeMode = [Windows.ResizeMode]::CanResizeWithGrip
    $script:BtnCompacto.Content = [string][char]0x25BE
  }
}

function Entrar-Mini {
  if ($script:Mini) { return }
  $script:Mini = $true
  $script:LarguraCheia = $script:Win.Width
  if (-not $script:Compacto) { $script:AlturaCheia = $script:Win.Height }
  $script:Painel.Visibility = [Windows.Visibility]::Collapsed
  $script:MiniPanel.Visibility = [Windows.Visibility]::Visible
  $script:Win.ResizeMode = [Windows.ResizeMode]::NoResize
  $script:Win.MinWidth = 0
  $script:Win.MinHeight = 0
  $script:Win.Width = $script:TamanhoMini
  $script:Win.Height = $script:TamanhoMini
  $script:Assinatura = ''
  $script:Moveu = $true
}
function Sair-Mini {
  if (-not $script:Mini) { return }
  $script:Mini = $false
  $script:MiniPanel.Visibility = [Windows.Visibility]::Collapsed
  $script:Painel.Visibility = [Windows.Visibility]::Visible
  $script:Win.MinWidth = 320
  $script:Win.Width = $script:LarguraCheia
  if ($script:Compacto) {
    $script:Win.MinHeight = 0
    $alturaTitulo = $script:TitleBar.ActualHeight
    if ($alturaTitulo -lt 20) { $alturaTitulo = 30 }
    $script:Win.Height = $alturaTitulo + 2
    $script:Win.ResizeMode = [Windows.ResizeMode]::NoResize
  } else {
    $script:Win.MinHeight = 120
    $script:Win.Height = $script:AlturaCheia
    $script:Win.ResizeMode = [Windows.ResizeMode]::CanResizeWithGrip
  }
  $script:Assinatura = ''
  $script:Moveu = $true
  Atualizar
}

$script:TitleBar.Add_MouseLeftButtonDown({
  param($sender, $e)
  if ($e.ClickCount -eq 2) { Alternar-Compacto } else { try { $script:Win.DragMove() } catch { } }
})
$script:BtnMini.Add_Click({ Entrar-Mini })
$script:MiniPanel.Add_MouseLeftButtonDown({
  param($sender, $e)
  # arrasta; se soltou praticamente no mesmo lugar, foi um clique: volta ao tamanho normal
  $l0 = $script:Win.Left; $t0 = $script:Win.Top
  try { $script:Win.DragMove() } catch { }
  if (([math]::Abs($script:Win.Left - $l0) -lt 4) -and ([math]::Abs($script:Win.Top - $t0) -lt 4)) { Sair-Mini }
  $e.Handled = $true
})
$script:TitleBar.Add_MouseWheel({
  param($sender, $e)
  $passo = 0.05
  if ($e.Delta -lt 0) { $passo = -0.05 }
  Aplicar-Brilho ($script:BrilhoValor + $passo)
  $script:Moveu = $true
  $e.Handled = $true
})
$script:Brilho.Add_ValueChanged({
  param($sender, $e)
  Aplicar-Brilho ([double]$e.NewValue)
  $script:Moveu = $true
})
$script:BtnFechar.Add_Click({ $script:Win.Close() })
$script:BtnCompacto.Add_Click({ Alternar-Compacto })
$script:BtnSom.Add_Click({ $script:Mudo = -not $script:Mudo; Atualizar-BotaoSom })
$script:Win.Add_Closing({ Salvar-Posicao })
$script:Win.Add_LocationChanged({ $script:Moveu = $true })

$script:Timer = New-Object Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(1500)
$script:Timer.Add_Tick({ Atualizar; if ($script:Moveu -and (($script:Tick % 4) -eq 0)) { $script:Moveu = $false; Salvar-Posicao } })

Aplicar-Brilho $script:BrilhoValor
Carregar-Posicao
Atualizar-BotaoSom
Atualizar
$script:Timer.Start()
Log 'overlay aberto'
[void]$script:Win.ShowDialog()
$script:Timer.Stop()
Log 'overlay fechado'
