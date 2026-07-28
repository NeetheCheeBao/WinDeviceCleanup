#Requires -Version 5.1
#  https://github.com/NeetheCheeBao
#  提权
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

#  隐藏控制台窗口
if (-not ('Hide.Win32' -as [type])) {
    Add-Type -Name Win32 -Namespace Hide -MemberDefinition '
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    ' -ErrorAction SilentlyContinue
}
try { [Hide.Win32]::ShowWindow([Hide.Win32]::GetConsoleWindow(), 0) } catch {}

#  WPF 程序集
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

#  预编译 SetupAPI 辅助类，以便首次移除时即可使用
if (-not ([System.Management.Automation.PSTypeName]'SetupApiRemove').Type) {
    Add-Type -Language CSharp -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class SetupApiRemove {
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)]
    static extern IntPtr SetupDiGetClassDevsEx(ref Guid ClassGuid, string Enumerator, IntPtr hwndParent,
        uint Flags, IntPtr DeviceInfoSet, string MachineName, IntPtr Reserved);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)]
    static extern bool SetupDiEnumDeviceInfo(IntPtr DeviceInfoSet, uint MemberIndex, ref SP_DEVINFO_DATA DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)]
    static extern bool SetupDiGetDeviceInstanceId(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData,
        System.Text.StringBuilder DeviceInstanceId, uint DeviceInstanceIdSize, out uint RequiredSize);
    [DllImport("setupapi.dll", SetLastError=true)]
    static extern bool SetupDiRemoveDevice(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData);
    [DllImport("setupapi.dll", SetLastError=true)]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVINFO_DATA {
        public uint   cbSize;
        public Guid   ClassGuid;
        public uint   DevInst;
        public IntPtr Reserved;
    }

    const uint DIGCF_ALLCLASSES = 0x04;
    static readonly IntPtr INVALID_HANDLE = new IntPtr(-1);

    public static bool Remove(string instanceId) {
        Guid empty = Guid.Empty;
        IntPtr devs = SetupDiGetClassDevsEx(ref empty, null, IntPtr.Zero, DIGCF_ALLCLASSES, IntPtr.Zero, null, IntPtr.Zero);
        if (devs == INVALID_HANDLE) return false;
        try {
            SP_DEVINFO_DATA data = new SP_DEVINFO_DATA();
            data.cbSize = (uint)Marshal.SizeOf(data);
            for (uint i = 0; SetupDiEnumDeviceInfo(devs, i, ref data); i++) {
                var sb = new System.Text.StringBuilder(512);
                uint needed;
                if (!SetupDiGetDeviceInstanceId(devs, ref data, sb, (uint)sb.Capacity, out needed)) continue;
                if (string.Equals(sb.ToString(), instanceId, StringComparison.OrdinalIgnoreCase))
                    return SetupDiRemoveDevice(devs, ref data);
            }
            return false;
        } finally { SetupDiDestroyDeviceInfoList(devs); }
    }
}
'@
}

#  缓存画刷转换器（避免每次取色都重新实例化）
$script:BrushConv = [System.Windows.Media.BrushConverter]::new()
function New-Brush { param([string]$hex); $script:BrushConv.ConvertFromString($hex) }

#  XAML 解析器 — 使用 XmlReader.Create（无中间 DOM）
function ConvertFrom-XamlString {
    param([string]$s)
    $xr = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($s.Trim()))
    return [System.Windows.Markup.XamlReader]::Load($xr)
}

#  主窗口 XAML
$mainXaml = @'
<Window
  xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="WinDeviceCleanup"
  Width="840" Height="640"
  MinWidth="640" MinHeight="460"
  WindowStartupLocation="CenterScreen"
  Background="Transparent"
  Foreground="#E8E8F0"
  FontFamily="Segoe UI"
  WindowStyle="None"
  AllowsTransparency="True"
  ResizeMode="CanResize">

  <Window.Resources>

    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background" Value="#3B82F6"/><Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,10"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#2563EB"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter TargetName="bd" Property="Background" Value="#1D4ED8"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False">
                <Setter TargetName="bd" Property="Background" Value="#1A1A24"/><Setter Property="Foreground" Value="#374151"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ConfirmBtn" TargetType="Button">
      <Setter Property="Background" Value="#16A34A"/><Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,10"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#22C55E"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter TargetName="bd" Property="Background" Value="#15803D"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False">
                <Setter TargetName="bd" Property="Background" Value="#1A1A24"/><Setter Property="Foreground" Value="#374151"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostBtn" TargetType="Button">
      <Setter Property="Background" Value="#1C1C26"/><Setter Property="Foreground" Value="#9CA3AF"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="14,8"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}" BorderBrush="#252530" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#252530"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False">
                <Setter TargetName="bd" Property="Background" Value="#111118"/><Setter Property="Foreground" Value="#374151"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#6B7280"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Width" Value="32"/><Setter Property="Height" Value="26"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#252530"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CloseBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#6B7280"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Width" Value="32"/><Setter Property="Height" Value="26"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#7F1D1D"/><Setter Property="Foreground" Value="#EF4444"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Width" Value="5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid>
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="#2D2D3D" CornerRadius="3"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Grid x:Name="RootGrid">
    <Border x:Name="MainBorder" CornerRadius="12" Background="#0A0A0F" BorderBrush="#1E1E2E" BorderThickness="1" Margin="4">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="50"/><RowDefinition Height="*"/><RowDefinition Height="58"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#0D0D15" CornerRadius="12,12,0,0">
          <Grid Margin="18,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse Width="7" Height="7" Fill="#3B82F6" Margin="0,0,9,0"/>
              <TextBlock Text="Device"    FontSize="13" FontWeight="Bold" Foreground="#3B82F6" VerticalAlignment="Center"/>
              <TextBlock Text=" Cleanup" FontSize="13" FontWeight="Bold" Foreground="#E8E8F0" VerticalAlignment="Center"/>
              <Border Background="#1C1C26" CornerRadius="4" Padding="8,2" Margin="12,0,0,0">
                <TextBlock Text="NeetheCheeBao" FontSize="10" Foreground="#2D3748" FontWeight="SemiBold" VerticalAlignment="Center"/>
              </Border>
              <Border x:Name="GithubBtn" Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="8,2" Margin="8,0,0,0" Cursor="Hand">
                <TextBlock Text="Go to Github" FontSize="10" Foreground="#3B82F6" VerticalAlignment="Center"/>
              </Border>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Button x:Name="BtnMinimize" Content="&#x2014;" Style="{StaticResource WinBtn}"/>
              <Button x:Name="BtnClose"    Content="&#x2715;" Style="{StaticResource CloseBtn}" Margin="4,0,0,0"/>
            </StackPanel>
          </Grid>
        </Border>
        <Grid Grid.Row="1" Margin="16,12,16,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="205"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid Grid.Column="0" Margin="0,0,0,6">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="#111118" CornerRadius="10" Padding="14,12" BorderBrush="#1E1E2E" BorderThickness="1" Margin="0,0,0,8">
              <StackPanel>
                <TextBlock Text="状态" FontSize="10" FontWeight="Bold" Foreground="#374151" Margin="0,0,0,8"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                  <Ellipse x:Name="StatusDot" Width="7" Height="7" Fill="#374151" Margin="0,0,7,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="StatusLabel" Text="准备扫描" Foreground="#6B7280" FontSize="12"/>
                </StackPanel>
                <Border Background="#0D0D15" CornerRadius="3" Height="4">
                  <Border x:Name="ProgressBar" Background="#3B82F6" CornerRadius="3" Width="0" HorizontalAlignment="Left" Height="4"/>
                </Border>
              </StackPanel>
            </Border>

            <Border Grid.Row="1" Background="#111118" CornerRadius="10" Padding="14,12" BorderBrush="#1E1E2E" BorderThickness="1" Margin="0,0,0,8">
              <StackPanel>
                <TextBlock Text="扫描结果" FontSize="10" FontWeight="Bold" Foreground="#374151" Margin="0,0,0,10"/>
                <TextBlock Text="幽灵设备" Foreground="#4B5563" FontSize="11"/>
                <TextBlock Text="可从注册表移除" Foreground="#252535" FontSize="9" Margin="0,1,0,2"/>
                <TextBlock x:Name="TxtGhostCount"     Text="-" Foreground="#EF4444" FontSize="24" FontWeight="Bold" Margin="0,1,0,6"/>
                <Border Background="#1C1C26" Height="1" Margin="0,0,0,8"/>
                <TextBlock Text="受保护" Foreground="#4B5563" FontSize="11"/>
                <TextBlock Text="已配置 CPU 亲和性" Foreground="#252535" FontSize="9" Margin="0,1,0,2"/>
                <TextBlock x:Name="TxtProtectedCount" Text="-" Foreground="#F59E0B" FontSize="24" FontWeight="Bold" Margin="0,1,0,6"/>
                <Border Background="#1C1C26" Height="1" Margin="0,0,0,8"/>
                <TextBlock Text="已移除" Foreground="#4B5563" FontSize="11"/>
                <TextBlock Text="本次会话" Foreground="#252535" FontSize="9" Margin="0,1,0,2"/>
                <TextBlock x:Name="TxtRemovedCount"   Text="0" Foreground="#22C55E" FontSize="24" FontWeight="Bold" Margin="0,1,0,0"/>
              </StackPanel>
            </Border>

            <Border Grid.Row="2" Background="#111118" CornerRadius="10" Padding="14,12" BorderBrush="#1E2E1E" BorderThickness="1">
              <StackPanel>
                <TextBlock Text="说明" FontSize="10" FontWeight="Bold" Foreground="#374151" Margin="0,0,0,6"/>
                <TextBlock TextWrapping="Wrap" Foreground="#374151" FontSize="10" LineHeight="15">移除先前连接、现已不存在的幽灵设备。降低 IRQ 开销，减少输入延迟，让操作更顺滑。收益随移除数量增加。已配置 CPU 亲和性的设备始终保留。</TextBlock>
              </StackPanel>
            </Border>

          </Grid>
          <Grid Grid.Column="2">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="0,0,0,8">
              <TextBlock Text="检测到的设备" FontSize="10" FontWeight="Bold" Foreground="#374151" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="BtnSelectAll"  Content="全选" Style="{StaticResource GhostBtn}" Padding="11,5"/>
                <Button x:Name="BtnSelectNone" Content="取消"       Style="{StaticResource GhostBtn}" Padding="11,5" Margin="6,0,0,0"/>
              </StackPanel>
            </Grid>

            <Border Grid.Row="1" Background="#111118" CornerRadius="10" BorderBrush="#1E1E2E" BorderThickness="1">
              <Grid>
                <ScrollViewer x:Name="EmptyState" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="2,0,6,0">
                  <StackPanel MaxWidth="480" HorizontalAlignment="Center" Margin="16,14,16,14">
                    <StackPanel HorizontalAlignment="Center" Margin="0,0,0,12">
                      <TextBlock Text="[ ]" FontSize="26" Foreground="#1C1C2E" HorizontalAlignment="Center"
                                 FontFamily="Consolas" Margin="0,0,0,8"/>
                      <TextBlock Text="Win Ghost Device Cleanup" Foreground="#4B5563" FontSize="14"
                                 FontWeight="SemiBold" HorizontalAlignment="Center"/>
                      <TextBlock Text="v1.0" Foreground="#252535" FontSize="10"
                                 HorizontalAlignment="Center" Margin="0,3,0,0"/>
                    </StackPanel>
                    <TextBlock TextWrapping="Wrap" Foreground="#374151" FontSize="11" LineHeight="17"
                               TextAlignment="Center" Margin="0,0,0,12">
                      扫描并移除由已断开 USB 外设留下的幽灵设备。
                      提升系统响应速度，减少驱动冲突，加快设备初始化。
                      适合竞技玩家与进阶用户。
                    </TextBlock>
                    <Border Background="#1A1A28" Height="1" Margin="0,0,0,12"/>
                    <TextBlock Text="工具功能" FontSize="9" FontWeight="Bold" Foreground="#252535"
                               HorizontalAlignment="Center" Margin="0,0,0,8"/>
                    <StackPanel HorizontalAlignment="Left" Margin="12,4,0,0">
                      <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <Ellipse Width="4" Height="4" Fill="#3B82F6" Margin="0,5,8,0" VerticalAlignment="Top"/>
                        <TextBlock TextWrapping="Wrap" Foreground="#374151" FontSize="11" LineHeight="16">扫描 Unknown 设备（错误代码 45）— 硬件已不再连接</TextBlock>
                      </StackPanel>
                      <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <Ellipse Width="4" Height="4" Fill="#3B82F6" Margin="0,5,8,0" VerticalAlignment="Top"/>
                        <TextBlock TextWrapping="Wrap" Foreground="#374151" FontSize="11" LineHeight="16">保留已配置 CPU 亲和性的设备（IRQ 绑定）</TextBlock>
                      </StackPanel>
                      <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <Ellipse Width="4" Height="4" Fill="#3B82F6" Margin="0,5,8,0" VerticalAlignment="Top"/>
                        <TextBlock TextWrapping="Wrap" Foreground="#374151" FontSize="11" LineHeight="16">通过 pnputil.exe（Windows 原生设备管理工具）移除幽灵条目</TextBlock>
                      </StackPanel>
                    </StackPanel>
                    <Border Background="#1A1A28" Height="1" Margin="0,10,0,12"/>
                    <TextBlock Text="收益" FontSize="9" FontWeight="Bold" Foreground="#252535"
                               HorizontalAlignment="Center" Margin="0,0,0,8"/>
                    <UniformGrid Columns="3" Margin="12,0,12,0">
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="更低输入延迟" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="无 IRQ 冲突" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="更干净注册表" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="更快启动" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="更快 USB 初始化" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                      <Border Background="#0D1520" BorderBrush="#1A2535" BorderThickness="1" CornerRadius="4" Padding="0,5" Margin="2,0,2,4">
                        <TextBlock Text="竞技优势" Foreground="#374151" FontSize="10" HorizontalAlignment="Center"/>
                      </Border>
                    </UniformGrid>
                  </StackPanel>
                </ScrollViewer>
                <ScrollViewer x:Name="DeviceScroller" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="2,2,8,2" Visibility="Collapsed">
                  <StackPanel x:Name="DeviceList" Margin="6"/>
                </ScrollViewer>
              </Grid>
            </Border>

            <Border Grid.Row="2" Background="#0D0D15" CornerRadius="8" BorderBrush="#1C1C26" BorderThickness="1" Margin="0,8,0,6" Height="46">
              <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto" Padding="2">
                <TextBlock x:Name="LogOutput" TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" Foreground="#374151" Padding="12,7" Text="// 点击「扫描系统」开始"/>
              </ScrollViewer>
            </Border>
          </Grid>
        </Grid>
        <Border Grid.Row="2" Background="#0D0D15" CornerRadius="0,0,12,12" BorderBrush="#1E1E2E" BorderThickness="0,1,0,0">
          <Grid Margin="16,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="BtnScan"   Content="  扫描系统  "     Style="{StaticResource PrimaryBtn}"/>
              <Button x:Name="BtnRemove" Content="  移除所选  " Style="{StaticResource ConfirmBtn}" IsEnabled="False" Margin="12,0,0,0"/>
              <Button x:Name="BtnClear"  Content="清空"               Style="{StaticResource GhostBtn}"  IsEnabled="False" Margin="10,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <TextBlock Text="WinDeviceCleanup v1.0" Foreground="#3B82F6" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
        </Border>

      </Grid>
    </Border>
    <Thumb x:Name="ThumbL"  Width="5"  HorizontalAlignment="Left"   VerticalAlignment="Stretch" Margin="0,16,0,16" Opacity="0" Cursor="SizeWE"/>
    <Thumb x:Name="ThumbR"  Width="5"  HorizontalAlignment="Right"  VerticalAlignment="Stretch" Margin="0,16,0,16" Opacity="0" Cursor="SizeWE"/>
    <Thumb x:Name="ThumbT"  Height="5" VerticalAlignment="Top"      HorizontalAlignment="Stretch" Margin="16,0,16,0" Opacity="0" Cursor="SizeNS"/>
    <Thumb x:Name="ThumbB"  Height="5" VerticalAlignment="Bottom"   HorizontalAlignment="Stretch" Margin="16,0,16,0" Opacity="0" Cursor="SizeNS"/>
    <Thumb x:Name="ThumbTL" Width="14" Height="14" HorizontalAlignment="Left"  VerticalAlignment="Top"    Opacity="0" Cursor="SizeNWSE"/>
    <Thumb x:Name="ThumbTR" Width="14" Height="14" HorizontalAlignment="Right" VerticalAlignment="Top"    Opacity="0" Cursor="SizeNESW"/>
    <Thumb x:Name="ThumbBL" Width="14" Height="14" HorizontalAlignment="Left"  VerticalAlignment="Bottom" Opacity="0" Cursor="SizeNESW"/>
    <Thumb x:Name="ThumbBR" Width="14" Height="14" HorizontalAlignment="Right" VerticalAlignment="Bottom" Opacity="0" Cursor="SizeNWSE"/>
    <Path Data="M 0 10 L 10 0 M 3 10 L 10 3 M 7 10 L 10 7"
          Stroke="#252530" StrokeThickness="1.2"
          HorizontalAlignment="Right" VerticalAlignment="Bottom"
          Margin="0,0,7,7" IsHitTestVisible="False"/>
  </Grid>
</Window>
'@

#  确认对话框
function Show-ConfirmDialog {
    param([string]$message, [string]$warning = '')
    $safeMsg = [System.Security.SecurityElement]::Escape($message)
    $warnXml = if ($warning) { '<TextBlock Text="' + [System.Security.SecurityElement]::Escape($warning) + '" TextWrapping="Wrap" Foreground="#F59E0B" FontSize="11" Margin="0,8,0,0"/>' } else { '' }
    $ns  = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
    $tNo = '<Button.Template><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="7"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#252530"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template>'
    $tYes= '<Button.Template><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="7"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#22C55E"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#15803D"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template>'
    $dx  = '<Window ' + $ns + ' Width="380" SizeToContent="Height" WindowStartupLocation="CenterOwner" Background="Transparent" WindowStyle="None" AllowsTransparency="True" ResizeMode="NoResize" ShowInTaskbar="False">'
    $dx += '<Border Padding="12" Background="#06060C" CornerRadius="14"><Border CornerRadius="10" Background="#111118" BorderBrush="#2D2D40" BorderThickness="1"><StackPanel Margin="22,18,22,18">'
    $dx += '<StackPanel Orientation="Horizontal" Margin="0,0,0,14"><Border Background="#1C1020" CornerRadius="6" Width="30" Height="30" Margin="0,0,12,0">'
    $dx += '<TextBlock Text="!" FontSize="15" FontWeight="Bold" Foreground="#EF4444" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
    $dx += '</Border><TextBlock Text="确认移除" FontSize="14" FontWeight="SemiBold" Foreground="#E8E8F0" VerticalAlignment="Center"/></StackPanel>'
    $dx += '<TextBlock Text="' + $safeMsg + '" TextWrapping="Wrap" Foreground="#9CA3AF" FontSize="12" LineHeight="18"/>'
    $dx += $warnXml
    $dx += '<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">'
    $dx += '<Button x:Name="BtnNo"  Content="取消" Width="88" Height="34" FontSize="12" FontWeight="SemiBold" Foreground="#9CA3AF" Background="#1C1C26" BorderBrush="#252530" BorderThickness="1" Cursor="Hand" Margin="0,0,8,0">' + $tNo  + '</Button>'
    $dx += '<Button x:Name="BtnYes" Content="移除" Width="88" Height="34" FontSize="12" FontWeight="SemiBold" Foreground="White"   Background="#16A34A" BorderThickness="0" Cursor="Hand">'                                      + $tYes + '</Button>'
    $dx += '</StackPanel></StackPanel></Border></Border></Window>'
    $dlg = ConvertFrom-XamlString $dx
    $dlg.Owner = $script:Win
    $script:ConfirmResult = $false
    $dlg.FindName('BtnYes').Add_Click({ $script:ConfirmResult = $true;  $dlg.Close() })
    $dlg.FindName('BtnNo').Add_Click({  $script:ConfirmResult = $false; $dlg.Close() })
    $dlg.Add_MouseLeftButtonDown({ param($s,$e); if ($e.Source -isnot [System.Windows.Controls.Button]) { $dlg.DragMove() } })
    $dlg.ShowDialog() | Out-Null
    return $script:ConfirmResult
}

#  进度对话框,实时移除反馈
function Show-ProgressDialog {
    param([System.Collections.ArrayList]$devices)

    $ns = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

    # 先将 ID 提取为纯字符串,供 XAML 中的 $total 以及 runspace 使用
    # PSCustomObject 跨 runspace 序列化不干净，字符串可以
    $instanceIds = [string[]]@($devices | ForEach-Object { ([string]$_.InstanceId).Trim() } | Where-Object { $_ -ne '' })
    $total       = $instanceIds.Count

    $closeTpl = '<Button.Template><ControlTemplate TargetType="Button"><Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#22C55E"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="#15803D"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Button.Template>'

    $px  = '<Window ' + $ns + ' Width="380" SizeToContent="Height" WindowStartupLocation="Manual" Background="Transparent" WindowStyle="None" AllowsTransparency="True" ResizeMode="NoResize" ShowInTaskbar="False">'
    $px += '<Border Padding="10" Background="#06060C" CornerRadius="14">'
    $px += '<Border CornerRadius="10" Background="#111118" BorderBrush="#2D2D40" BorderThickness="1">'
    $px += '<StackPanel Margin="22,18,22,18">'
    # 标题
    $px += '<StackPanel Orientation="Horizontal" Margin="0,0,0,14">'
    $px += '<Border Background="#0D1A0D" CornerRadius="6" Width="28" Height="28" Margin="0,0,10,0">'
    $px += '<TextBlock Text="&#x2715;" FontSize="12" FontWeight="Bold" Foreground="#22C55E" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
    $px += '</Border>'
    $px += '<TextBlock Text="正在移除设备" FontSize="13" FontWeight="SemiBold" Foreground="#E8E8F0" VerticalAlignment="Center"/>'
    $px += '</StackPanel>'
    # 计数行
    $px += '<Grid Margin="0,0,0,8">'
    $px += '<StackPanel Orientation="Horizontal" VerticalAlignment="Center">'
    $px += '<Ellipse x:Name="PulseDot" Width="7" Height="7" Fill="#3B82F6" Margin="0,0,7,0" VerticalAlignment="Center"/>'
    $px += '<TextBlock Text="正在移除设备" Foreground="#6B7280" FontSize="11" VerticalAlignment="Center"/>'
    $px += '<TextBlock x:Name="CounterLabel" Text="  0 / ' + $total + '" Foreground="#E8E8F0" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>'
    $px += '</StackPanel>'
    $px += '<TextBlock x:Name="PctLabel" Text="0 %" HorizontalAlignment="Right" Foreground="#3B82F6" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>'
    $px += '</Grid>'
    # 进度条
    $px += '<Border Background="#0D0D15" CornerRadius="4" Height="5" Margin="0,0,0,12">'
    $px += '<Border x:Name="ProgFill" Background="#3B82F6" CornerRadius="4" Width="0" HorizontalAlignment="Left" Height="5"/>'
    $px += '</Border>'
    # 确认消息（完成前隐藏）
    $px += '<Border x:Name="ConfirmBorder" Background="#0D1A0D" BorderBrush="#14532D" BorderThickness="1" CornerRadius="7" Padding="12,8" Margin="0,0,0,12" Visibility="Collapsed">'
    $px += '<StackPanel Orientation="Horizontal">'
    $px += '<TextBlock Text="&#x2714;" FontSize="12" Foreground="#22C55E" Margin="0,0,8,0" VerticalAlignment="Center"/>'
    $px += '<TextBlock x:Name="ConfirmMsg" Text="" FontSize="11" FontWeight="SemiBold" Foreground="#22C55E" VerticalAlignment="Center"/>'
    $px += '</StackPanel>'
    $px += '</Border>'
    # 完成按钮
    $px += '<Button x:Name="BtnClose" Content="  完成  " Width="100" Height="32" HorizontalAlignment="Right" FontSize="12" FontWeight="SemiBold" Foreground="White" Background="#16A34A" BorderThickness="0" Cursor="Hand" Visibility="Collapsed">' + $closeTpl + '</Button>'
    $px += '</StackPanel></Border></Border></Window>'

    $pdlg           = ConvertFrom-XamlString $px
    $pdlg.Owner     = $script:Win
    $pCounter       = $pdlg.FindName('CounterLabel')
    $pPct           = $pdlg.FindName('PctLabel')
    $pProgFill      = $pdlg.FindName('ProgFill')
    $pConfirmBorder = $pdlg.FindName('ConfirmBorder')
    $pConfirmMsg    = $pdlg.FindName('ConfirmMsg')
    $pBtnClose      = $pdlg.FindName('BtnClose')
    $pPulseDot      = $pdlg.FindName('PulseDot')

    $pBtnClose.Add_Click({ $pdlg.Close() })
    $pdlg.Add_MouseLeftButtonDown({ param($s,$e); if ($e.Source -isnot [System.Windows.Controls.Button]) { $pdlg.DragMove() } })

    # 修复：在 SizeToContent 解析出实际尺寸后手动居中
    $pdlg.Add_ContentRendered({
        $owner = $pdlg.Owner
        if ($owner) {
            $pdlg.Left = $owner.Left + ($owner.ActualWidth  - $pdlg.ActualWidth)  / 2
            $pdlg.Top  = $owner.Top  + ($owner.ActualHeight - $pdlg.ActualHeight) / 2
        }
    })

    # 圆点脉冲动画（UI 线程定时器 — 安全，无跨线程访问）
    $dotColors = @('#3B82F6','#60A5FA','#93C5FD','#60A5FA','#3B82F6','#1D4ED8','#2563EB')
    $script:_dotIdx = 0
    $dotTimer  = New-Object System.Windows.Threading.DispatcherTimer
    $dotTimer.Interval = [TimeSpan]::FromMilliseconds(120)
    $dotTimer.Add_Tick({
        $pPulseDot.Fill = New-Brush $dotColors[$script:_dotIdx % $dotColors.Count]
        $script:_dotIdx++
    })
    $dotTimer.Start()

    # 在 runspace 与 UI 轮询定时器之间传递的共享状态袋
    $script:_progBag = [hashtable]::Synchronized(@{ Done=0; Ok=0; Fail=0; Finished=$false })
    $progBag = $script:_progBag

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($ids, $total, $progBag)

        # 池：最多 12 个并发移除
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 12)
        $pool.Open()

        # 预先启动全部任务
        $jobs = [System.Collections.Generic.List[object]]::new()
        foreach ($id in $ids) {
            $j = [System.Management.Automation.PowerShell]::Create()
            $j.RunspacePool = $pool
            [void]$j.AddScript({
                param($id)
                $removed = $false
                try { Get-PnpDevice -InstanceId $id -EA Stop | Remove-PnpDevice -Confirm:$false -EA Stop; $removed = $true } catch {}
                if (-not $removed) {
                    try { & pnputil.exe /remove-device "$id" 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $removed = $true } } catch {}
                }
                if (-not $removed) {
                    try { & reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Enum\$id" /f 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $removed = $true } } catch {}
                }
                return $removed
            }).AddArgument($id)
            $jobs.Add([PSCustomObject]@{ J = $j; H = $j.BeginInvoke() })
        }

        # 轮询直至全部完成 — 用简单整数递增更新 progBag
        $pending = [System.Collections.Generic.List[object]]::new($jobs)
        $ok = 0; $fail = 0

        while ($pending.Count -gt 0) {
            $done_items = @($pending | Where-Object { $_.H.IsCompleted })
            foreach ($item in $done_items) {
                $result = $false
                try { $r = $item.J.EndInvoke($item.H); if ($r -and $r.Count -gt 0) { $result = [bool]$r[0] } } catch {}
                try { $item.J.Dispose() } catch {}
                $pending.Remove($item) | Out-Null
                if ($result) { $ok++ } else { $fail++ }
                $progBag['Done'] = $ok + $fail
                $progBag['Ok']   = $ok
                $progBag['Fail'] = $fail
            }
            if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 20 }
        }

        $pool.Close(); $pool.Dispose()
        $progBag['Ok']       = $ok
        $progBag['Fail']     = $fail
        $progBag['Done']     = $ok + $fail
        $progBag['Finished'] = $true

    }).AddParameters(@{ ids = $instanceIds; total = $total; progBag = $progBag })

    $handle = $ps.BeginInvoke()

    #  UI 轮询定时器：读取共享状态袋，以 30fps（33ms）更新控件
    $pollT = New-Object System.Windows.Threading.DispatcherTimer
    $pollT.Interval = [TimeSpan]::FromMilliseconds(33)
    $pollT.Add_Tick({
        $done  = [int]$progBag['Done']
        $pct   = if ($total -gt 0) { [Math]::Round(($done / $total) * 100) } else { 100 }

        $pCounter.Text = '  ' + $done + ' / ' + $total
        $pPct.Text     = $pct.ToString() + ' %'
        $trackW = $pProgFill.Parent.ActualWidth
        if ($trackW -gt 0) {
            $pProgFill.Width = [Math]::Max(0, [Math]::Min($trackW, $trackW * ($pct / 100.0)))
        }

        if ($progBag['Finished']) {
            $pollT.Stop()
            $dotTimer.Stop()

            $ok   = [int]$progBag['Ok']
            $fail = [int]$progBag['Fail']
            $conv = [System.Windows.Media.BrushConverter]::new()
            $pPulseDot.Fill = $conv.ConvertFromString('#22C55E')

            if ($fail -gt 0) {
                $pConfirmMsg.Text               = '已移除 ' + $ok.ToString() + ' 个 — 失败 ' + $fail.ToString() + ' 个'
                $pConfirmBorder.Background      = $conv.ConvertFromString('#1A0D0D')
                $pConfirmBorder.BorderBrush     = $conv.ConvertFromString('#7F1D1D')
                $pConfirmMsg.Foreground         = $conv.ConvertFromString('#EF4444')
            } else {
                $pConfirmMsg.Text = '已成功移除全部 ' + $ok.ToString() + ' 个设备！'
            }
            $pConfirmBorder.Visibility = [System.Windows.Visibility]::Visible
            $pBtnClose.Visibility      = [System.Windows.Visibility]::Visible

            try { $ps.EndInvoke($handle) } catch {}
            try { $ps.Dispose() }          catch {}
            try { $rs.Dispose() }          catch {}
        }
    })
    $pollT.Start()

    $pdlg.ShowDialog() | Out-Null
    # 若对话框在完成前关闭，确保定时器已停止
    try { $pollT.Stop() }  catch {}
    try { $dotTimer.Stop() } catch {}
}

#  解析窗口并绑定命名控件
$script:Win = ConvertFrom-XamlString $mainXaml

foreach ($n in @('BtnScan','BtnRemove','BtnClear','BtnSelectAll','BtnSelectNone','BtnClose','BtnMinimize',
                 'DeviceList','EmptyState','DeviceScroller','LogOutput','LogScroller','StatusDot',
                 'StatusLabel','ProgressBar','TxtGhostCount','TxtProtectedCount','TxtRemovedCount',
                 'GithubBtn','ThumbL','ThumbR','ThumbT','ThumbB','ThumbTL','ThumbTR','ThumbBL','ThumbBR')) {
    Set-Variable -Name "script:$n" -Value $script:Win.FindName($n)
}

#  脚本作用域状态
$script:DevicesToRemove  = @()
$script:DevicesProtected = @()
$script:RemovedTotal     = 0
$script:CheckBoxes       = [System.Collections.Generic.List[object]]::new()
$script:ScanRunspace     = $null
$script:ScanPS           = $null
$script:ScanHandle       = $null
$script:PollTimer        = $null
$script:RescanTimer      = $null
$script:ScanPct          = 0.0

#  UI 辅助函数
# 从后台线程调用时用 BeginInvoke（异步）避免阻塞；
# 已在 UI 线程时直接调用（例如 DispatcherTimer 回调）。
function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format 'HH:mm:ss'
    $action = [action]{
        $script:LogOutput.Text += "`n[$time]  $msg"
        $script:LogScroller.ScrollToBottom()
    }
    if ($script:Win.Dispatcher.CheckAccess()) { & $action }
    else { $script:Win.Dispatcher.BeginInvoke($action) | Out-Null }
}

function Set-StatusUI {
    param([string]$text, [string]$color)
    $action = [action]{
        $script:StatusLabel.Text = $text
        $script:StatusDot.Fill   = $script:BrushConv.ConvertFromString($color)
    }
    if ($script:Win.Dispatcher.CheckAccess()) { & $action }
    else { $script:Win.Dispatcher.BeginInvoke($action) | Out-Null }
}

function Set-ProgressUI {
    param([double]$pct)
    $action = [action]{
        $pw = $script:ProgressBar.Parent.ActualWidth
        if ($pw -gt 0) { $script:ProgressBar.Width = [Math]::Max(0, [Math]::Min($pw, $pw * $pct)) }
    }
    if ($script:Win.Dispatcher.CheckAccess()) { & $action }
    else { $script:Win.Dispatcher.BeginInvoke($action) | Out-Null }
}

#  直接构建分区标题 TextBlock
function New-SectionHeader {
    param([string]$text, [string]$color, [System.Windows.Thickness]$margin)
    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text       = $text
    $tb.FontSize   = 9
    $tb.FontWeight = [System.Windows.FontWeights]::Bold
    $tb.Foreground = New-Brush $color
    $tb.Margin     = $margin
    return $tb
}

#  直接构建分隔线 Border
function New-Separator {
    $b = [System.Windows.Controls.Border]::new()
    $b.Height     = 1
    $b.Background = New-Brush '#1C1C26'
    $b.Margin     = [System.Windows.Thickness]::new(0,5,0,5)
    return $b
}

#  直接用 WPF 构建设备行
function Add-DeviceRow {
    param($device, [bool]$isProtected)

    $devIdRaw = (([string]$device.InstanceId) -replace '[\r\n\t]', '').Trim()

    $outer = [System.Windows.Controls.Border]::new()
    $outer.CornerRadius    = [System.Windows.CornerRadius]::new(3)
    $outer.Margin          = [System.Windows.Thickness]::new(0,0,0,1)
    $outer.Padding         = [System.Windows.Thickness]::new(7,2,7,2)
    $outer.BorderThickness = [System.Windows.Thickness]::new(1)
    $outer.ToolTip         = $devIdRaw
    if ($isProtected) {
        $outer.Background  = New-Brush '#0E1118'
        $outer.BorderBrush = New-Brush '#1A2030'
    } else {
        $outer.Background  = New-Brush '#13111A'
        $outer.BorderBrush = New-Brush '#221A2E'
    }

    $grid = [System.Windows.Controls.Grid]::new()
    $c0   = [System.Windows.Controls.ColumnDefinition]::new()
    $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c1   = [System.Windows.Controls.ColumnDefinition]::new()
    $c1.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c0)
    [void]$grid.ColumnDefinitions.Add($c1)

    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.Orientation       = [System.Windows.Controls.Orientation]::Horizontal
    $sp.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($sp, 0)

    $cb = [System.Windows.Controls.CheckBox]::new()
    $cb.IsChecked         = if ($isProtected) { [System.Nullable[bool]]$false } else { [System.Nullable[bool]]$true }
    $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $cb.Margin            = [System.Windows.Thickness]::new(0,0,6,0)
    $cb.Foreground        = if ($isProtected) { New-Brush '#374151' } else { New-Brush '#E8E8F0' }
    $cb.Tag = if ($isProtected) { 'PROTECTED::' + $devIdRaw } else { $devIdRaw }
    $script:CheckBoxes.Add($cb)

    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width            = 4
    $dot.Height           = 4
    $dot.Margin           = [System.Windows.Thickness]::new(0,0,6,0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $dot.Fill             = if ($isProtected) { New-Brush '#1E3A5F' } else { New-Brush '#3B82F6' }

    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text              = $device.Name
    $tb.FontSize          = 11
    $tb.TextTrimming      = [System.Windows.TextTrimming]::CharacterEllipsis
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $tb.Foreground        = if ($isProtected) { New-Brush '#6B7280' } else { New-Brush '#D1D5DB' }

    [void]$sp.Children.Add($cb)
    [void]$sp.Children.Add($dot)
    [void]$sp.Children.Add($tb)

    $badge = [System.Windows.Controls.Border]::new()
    $badge.CornerRadius      = [System.Windows.CornerRadius]::new(2)
    $badge.Padding           = [System.Windows.Thickness]::new(5,1,5,1)
    $badge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $badge.Background        = if ($isProtected) { New-Brush '#0A1628' } else { New-Brush '#1A0F1F' }
    [System.Windows.Controls.Grid]::SetColumn($badge, 1)

    $badgeTb = [System.Windows.Controls.TextBlock]::new()
    $badgeTb.FontSize   = 8
    $badgeTb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $badgeTb.Text       = if ($isProtected) { '亲和性已配置' } else { '幽灵' }
    $badgeTb.Foreground = if ($isProtected) { New-Brush '#3B82F6' }   else { New-Brush '#A78BFA' }
    $badge.Child = $badgeTb

    [void]$grid.Children.Add($sp)
    [void]$grid.Children.Add($badge)
    $outer.Child = $grid

    [void]$script:DeviceList.Children.Add($outer)
}

#  重置全部 UI 状态
function Reset-UI {
    $script:DeviceList.Children.Clear()
    $script:CheckBoxes.Clear()
    $script:DevicesToRemove  = @()
    $script:DevicesProtected = @()
    $script:EmptyState.Visibility     = [System.Windows.Visibility]::Visible
    $script:DeviceScroller.Visibility = [System.Windows.Visibility]::Collapsed
    $script:TxtGhostCount.Text     = '-'
    $script:TxtProtectedCount.Text = '-'
    $script:BtnRemove.IsEnabled    = $false
    $script:BtnClear.IsEnabled     = $false
    Set-StatusUI '准备扫描' '#374151'
    Set-ProgressUI 0
}

#  窗口拖动
$script:Win.Add_MouseLeftButtonDown({
    param($s,$e)
    $src = $e.OriginalSource
    # 点击交互控件时不拖动
    $isInteractive = ($src -is [System.Windows.Controls.Primitives.ButtonBase]) -or
                     ($src -is [System.Windows.Controls.Primitives.TextBoxBase]) -or
                     ($src -is [System.Windows.Controls.ScrollBar]) -or
                     ($src -is [System.Windows.Controls.Primitives.Thumb])
    if (-not $isInteractive) { $script:Win.DragMove() }
})

#  关闭 / 最小化
$script:BtnClose.Add_Click({
    if ($script:PollTimer)    { $script:PollTimer.Stop();   $script:PollTimer   = $null }
    if ($script:RescanTimer)  { $script:RescanTimer.Stop(); $script:RescanTimer = $null }
    if ($script:ScanPS)       { try { $script:ScanPS.Stop() }       catch {} }
    if ($script:ScanRunspace) { try { $script:ScanRunspace.Dispose() } catch {} }
    $script:ScanPS = $script:ScanRunspace = $script:ScanHandle = $null
    $script:Win.Close()
})

$script:BtnMinimize.Add_Click({ $script:Win.WindowState = [System.Windows.WindowState]::Minimized })

#  GitHub 按钮
#  https://github.com/NeetheCheeBao
$script:GithubBtn.Add_MouseLeftButtonDown({ Start-Process 'https://github.com/NeetheCheeBao/WinDeviceCleanup' })
$script:GithubBtn.Add_MouseEnter({ $script:GithubBtn.Background = New-Brush '#111D2E' })
$script:GithubBtn.Add_MouseLeave({ $script:GithubBtn.Background = New-Brush '#0D1520' })
#  https://github.com/NeetheCheeBao

#  全选 / 取消全选
$script:BtnSelectAll.Add_Click({
    foreach ($cb in $script:CheckBoxes) {
        if (-not ($cb.Tag -is [string] -and $cb.Tag.StartsWith('PROTECTED::'))) {
            $cb.IsChecked = $true
        }
    }
})

$script:BtnSelectNone.Add_Click({ foreach ($cb in $script:CheckBoxes) { $cb.IsChecked = $false } })

#  扫描
$script:BtnScan.Add_Click({
    $script:BtnScan.IsEnabled = $script:BtnRemove.IsEnabled = $script:BtnClear.IsEnabled = $false
    $script:DeviceList.Children.Clear()
    $script:CheckBoxes.Clear()
    $script:DevicesToRemove  = @()
    $script:DevicesProtected = @()
    $script:EmptyState.Visibility     = [System.Windows.Visibility]::Collapsed
    $script:DeviceScroller.Visibility = [System.Windows.Visibility]::Visible

    Set-StatusUI '正在扫描系统...' '#3B82F6'
    Set-ProgressUI 0.08
    Write-Log '正在扫描...'

    $script:ScanRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:ScanRunspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $script:ScanRunspace.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $script:ScanRunspace.Open()

    $script:ScanPS = [System.Management.Automation.PowerShell]::Create()
    $script:ScanPS.Runspace = $script:ScanRunspace

    [void]$script:ScanPS.AddScript({

        function Test-HasRealAffinity {
            param([string]$InstanceId)
            try {
                $afPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy"
                if (Test-Path $afPath) {
                    $a = Get-ItemProperty -Path $afPath -ErrorAction SilentlyContinue
                    if ($null -ne $a.DevicePolicy -and $a.DevicePolicy -ge 3) { return $true }
                    if ($a.AssignmentSetOverride) {
                        foreach ($b in [byte[]]$a.AssignmentSetOverride) { if ($b -ne 0) { return $true } }
                    }
                }
                return $false
            } catch { return $false }
        }

        function Get-CleanId { param([string]$id); return ($id -replace '[\r\n\t]', '').Trim() }

        function New-DeviceObject { param($dev)
            [PSCustomObject]@{
                Name       = ([string]$dev.FriendlyName).Trim()
                InstanceId = Get-CleanId ([string]$dev.InstanceId)
                Status     = [string]$dev.Status
            }
        }

        $allRaw   = @(Get-PnpDevice -PresentOnly:$false -ErrorAction SilentlyContinue)
        $allDevs  = $allRaw | ForEach-Object { New-DeviceObject $_ }
        $ghosts   = @($allDevs | Where-Object { $_.Status -eq 'Unknown' })
        $seenIds  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $toRemove = [System.Collections.ArrayList]::new()
        $protected = [System.Collections.ArrayList]::new()

        foreach ($dev in $ghosts) {
            [void]$seenIds.Add($dev.InstanceId)
            if (Test-HasRealAffinity -InstanceId $dev.InstanceId) { [void]$protected.Add($dev) }
            else { [void]$toRemove.Add($dev) }
        }

        foreach ($dev in $allDevs) {
            if ($seenIds.Contains($dev.InstanceId)) { continue }
            if (Test-HasRealAffinity -InstanceId $dev.InstanceId) {
                [void]$seenIds.Add($dev.InstanceId)
                [void]$protected.Add($dev)
            }
        }

        return [PSCustomObject]@{ ToRemove = @($toRemove); Protected = @($protected) }
    })

    $script:ScanHandle = $script:ScanPS.BeginInvoke()
    $script:ScanPct    = 0.08

    $script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:PollTimer.Add_Tick({
        if ($script:ScanPct -lt 0.88) { $script:ScanPct += 0.04; Set-ProgressUI $script:ScanPct }

        if ($script:ScanHandle -and $script:ScanHandle.IsCompleted) {
            $script:PollTimer.Stop()
            $res = $null
            try { $res = $script:ScanPS.EndInvoke($script:ScanHandle) } catch {}
            try { $script:ScanPS.Dispose() }      catch {}
            try { $script:ScanRunspace.Dispose() } catch {}
            $script:ScanPS = $script:ScanRunspace = $script:ScanHandle = $null

            $scanResult = if ($res -and $res.Count -gt 0) { $res[0] } else { $null }

            if ($scanResult) {
                $script:DevicesToRemove  = @($scanResult.ToRemove  | Where-Object { $_ -ne $null })
                $script:DevicesProtected = @($scanResult.Protected | Where-Object { $_ -ne $null })
            } else {
                $script:DevicesToRemove  = @()
                $script:DevicesProtected = @()
                Write-Log '未发现设备。'
            }

            # 已在 UI 线程（DispatcherTimer 回调）— 直接调用 WPF，无需 Invoke
            $script:TxtGhostCount.Text     = $script:DevicesToRemove.Count.ToString()
            $script:TxtProtectedCount.Text = $script:DevicesProtected.Count.ToString()

            if ($script:DevicesToRemove.Count -gt 0) {
                [void]$script:DeviceList.Children.Add((New-SectionHeader '可移除的幽灵设备' '#A78BFA' ([System.Windows.Thickness]::new(2,3,0,4))))
                foreach ($d in $script:DevicesToRemove) { Add-DeviceRow -device $d -isProtected $false }
            }

            if ($script:DevicesProtected.Count -gt 0) {
                if ($script:DevicesToRemove.Count -gt 0) { [void]$script:DeviceList.Children.Add((New-Separator)) }
                [void]$script:DeviceList.Children.Add((New-SectionHeader 'CPU 亲和性保护' '#3B82F6' ([System.Windows.Thickness]::new(2,0,0,4))))
                foreach ($d in $script:DevicesProtected) { Add-DeviceRow -device $d -isProtected $true }
            }

            $scanTotal = $script:DevicesToRemove.Count + $script:DevicesProtected.Count

            if ($scanTotal -eq 0) {
                $script:EmptyState.Visibility     = [System.Windows.Visibility]::Visible
                $script:DeviceScroller.Visibility = [System.Windows.Visibility]::Collapsed
                Set-StatusUI '系统干净' '#22C55E'
                Write-Log '系统干净。'
            } elseif ($script:DevicesToRemove.Count -eq 0) {
                Set-StatusUI '发现受保护设备' '#F59E0B'
                Write-Log ('受保护：' + $script:DevicesProtected.Count + ' — 如需移除请手动勾选。')
                $script:BtnRemove.IsEnabled = $true
            } else {
                Set-StatusUI ('幽灵设备：' + $script:DevicesToRemove.Count) '#EF4444'
                Write-Log ('幽灵：' + $script:DevicesToRemove.Count + '   受保护：' + $script:DevicesProtected.Count)
                $script:BtnRemove.IsEnabled = $true
            }
            $script:BtnClear.IsEnabled = $script:BtnScan.IsEnabled = $true
            Set-ProgressUI 1.0
        }
    })
    $script:PollTimer.Start()
})

#  移除所选设备
$script:BtnRemove.Add_Click({
    $selected = [System.Collections.ArrayList]::new()

    foreach ($dev in $script:DevicesToRemove) {
        $id = (([string]$dev.InstanceId) -replace '[\r\n\t]', '').Trim()
        foreach ($cb in $script:CheckBoxes) {
            if ($cb.IsChecked -eq $true -and
                [string]::Equals((([string]$cb.Tag) -replace '[\r\n\t]', '').Trim(),
                                 $id, [StringComparison]::OrdinalIgnoreCase)) {
                [void]$selected.Add($dev); break
            }
        }
    }

    foreach ($dev in $script:DevicesProtected) {
        $id = 'PROTECTED::' + (([string]$dev.InstanceId) -replace '[\r\n\t]', '').Trim()
        foreach ($cb in $script:CheckBoxes) {
            if ($cb.IsChecked -eq $true -and
                [string]::Equals((([string]$cb.Tag) -replace '[\r\n\t]', '').Trim(),
                                 $id, [StringComparison]::OrdinalIgnoreCase)) {
                [void]$selected.Add($dev); break
            }
        }
    }

    if ($selected.Count -eq 0) { Write-Log '未选择设备。'; return }

    $protIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($dev in $script:DevicesProtected) {
        [void]$protIds.Add((([string]$dev.InstanceId) -replace '[\r\n\t]', '').Trim())
    }
    $protCount = ($selected | Where-Object {
        $protIds.Contains((([string]$_.InstanceId) -replace '[\r\n\t]', '').Trim())
    }).Count

    $warnLine = if ($protCount -gt 0) { "警告：包含 $protCount 个受保护设备。这将删除你的 IRQ 亲和性配置。" } else { '' }

    if (-not (Show-ConfirmDialog -message ('移除 ' + $selected.Count + ' 个设备？此操作无法撤销。') -warning $warnLine)) {
        Write-Log '已取消。'; return
    }

    $script:BtnRemove.IsEnabled = $script:BtnScan.IsEnabled = $false
    Set-StatusUI '正在移除设备...' '#EF4444'
    Write-Log ('正在移除 ' + $selected.Count + ' 个设备...')

    Show-ProgressDialog -devices $selected | Out-Null

    # 使用共享状态袋中的实际移除数量（由后台工作线程设置）
    $actualRemoved = if ($script:_progBag) { [int]$script:_progBag['Ok'] } else { $selected.Count }
    $script:RemovedTotal += $actualRemoved
    $script:TxtRemovedCount.Text = $script:RemovedTotal.ToString()
    Set-StatusUI '移除完成' '#22C55E'
    Write-Log '移除完成。正在重新扫描...'

    $script:RescanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:RescanTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $script:RescanTimer.Add_Tick({
        $script:RescanTimer.Stop()
        $script:RescanTimer = $null
        # 保护：仅在当前没有扫描进行时才自动重新扫描
        if ($script:BtnScan.IsEnabled -and $script:ScanHandle -eq $null) {
            $script:BtnScan.IsEnabled = $true
            $script:BtnScan.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }
    })
    $script:RescanTimer.Start()
})

#  清空按钮
$script:BtnClear.Add_Click({ Reset-UI; Write-Log '已清空。' })

#  通过 Thumb 手柄自定义调整大小
function Resize-Win {
    param([double]$dw, [double]$dh, [bool]$fromLeft, [bool]$fromTop)
    $minW = $script:Win.MinWidth; $minH = $script:Win.MinHeight
    if ($fromLeft) {
        $newW = $script:Win.Width - $dw
        if ($newW -lt $minW) { $dw = $script:Win.Width - $minW; $newW = $minW }
        $script:Win.Left += $dw; $script:Win.Width = $newW
    } elseif ($dw -ne 0) { $script:Win.Width = [Math]::Max($minW, $script:Win.Width + $dw) }
    if ($fromTop) {
        $newH = $script:Win.Height - $dh
        if ($newH -lt $minH) { $dh = $script:Win.Height - $minH; $newH = $minH }
        $script:Win.Top += $dh; $script:Win.Height = $newH
    } elseif ($dh -ne 0) { $script:Win.Height = [Math]::Max($minH, $script:Win.Height + $dh) }
}

$script:ThumbR.Add_DragDelta({  param($s,$e); Resize-Win  $e.HorizontalChange 0                 $false $false })
$script:ThumbL.Add_DragDelta({  param($s,$e); Resize-Win  $e.HorizontalChange 0                 $true  $false })
$script:ThumbB.Add_DragDelta({  param($s,$e); Resize-Win  0 $e.VerticalChange                   $false $false })
$script:ThumbT.Add_DragDelta({  param($s,$e); Resize-Win  0 $e.VerticalChange                   $false $true  })
$script:ThumbBR.Add_DragDelta({ param($s,$e); Resize-Win  $e.HorizontalChange $e.VerticalChange $false $false })
$script:ThumbBL.Add_DragDelta({ param($s,$e); Resize-Win  $e.HorizontalChange $e.VerticalChange $true  $false })
$script:ThumbTR.Add_DragDelta({ param($s,$e); Resize-Win  $e.HorizontalChange $e.VerticalChange $false $true  })
$script:ThumbTL.Add_DragDelta({ param($s,$e); Resize-Win  $e.HorizontalChange $e.VerticalChange $true  $true  })

#  显示窗口
$script:Win.ShowDialog() | Out-Null