using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Principal;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using WdcShell.Core;
using WdcShell.Services;

namespace WdcShell
{
    /// <summary>
    /// 界面逻辑：控件绑定、事件接线、列表渲染、界面状态更新。
    /// 对应 MainWindow.xaml（界面定义）。
    /// </summary>
    public static class MainWindow
    {
        /// <summary>程序版本，显示在窗口标题上。</summary>
        const string AppVersion = "2.0";

        // 绑定与接线

        /// <summary>把 XAML 里用 x:Name 命名的控件抓取到 AppState，供各模块使用。</summary>
        public static void Bind()
        {
            AppState.DeviceListPanel = (StackPanel)F("DeviceList");
            AppState.EmptyState = (ScrollViewer)F("EmptyState");
            AppState.DeviceScroller = (ScrollViewer)F("DeviceScroller");
            AppState.LogScroller = (ScrollViewer)F("LogScroller");
            AppState.LogOutput = (TextBlock)F("LogOutput");
            AppState.StatusLabel = (TextBlock)F("StatusLabel");
            AppState.PageTitle = (TextBlock)F("PageTitle");
            AppState.PageSubtitle = (TextBlock)F("PageSubtitle");
            AppState.GhostCount = (TextBlock)F("TxtGhostCount");
            AppState.ProtectedCount = (TextBlock)F("TxtProtectedCount");
            AppState.RemovedCount = (TextBlock)F("TxtRemovedCount");
            AppState.StatusBarMain = (TextBlock)F("SbMain");
            AppState.StatusBarCount = (TextBlock)F("SbCount");
            AppState.StatusDot = (Ellipse)F("StatusDot");
            AppState.ProgressFill = (Border)F("ProgressBar");
            AppState.BtnScan = (Button)F("BtnScan");
            AppState.BtnRemove = (Button)F("BtnRemove");
            AppState.BtnClear = (Button)F("BtnClear");
        }

        static object F(string name) { return AppState.Window.FindName(name); }

        /// <summary>接线所有按钮、菜单与快捷键。</summary>
        public static void WireEvents()
        {
            AppState.BtnScan.Click += delegate { Scan(); };
            AppState.BtnRemove.Click += delegate { Remove(); };
            AppState.BtnClear.Click += delegate { ClearAll(); };

            ((Button)F("BtnSelectAll")).Click += delegate { SelectAll(true); };
            ((Button)F("BtnSelectNone")).Click += delegate { SelectAll(false); };

            ((MenuItem)F("MiCheckUpdate")).Click += delegate { OpenProjectPage(); };
            ((MenuItem)F("MiOpenLog")).Click += delegate { OpenLogFolder(); };
            ((MenuItem)F("MiDiagnose")).Click += delegate { RunDiagnostics(); };

            // F5 = 重新扫描
            AppState.Window.InputBindings.Add(new KeyBinding(
                new RelayCommand(delegate { if (!AppState.Busy) Scan(); }), Key.F5, ModifierKeys.None));

            AppState.Window.Loaded += delegate
            {
                ApplyWindowTitle();
                SetStatus("准备扫描", "W32Faint");
                SetStatusBar("NeetheCheeBao");
            };

            AppState.Window.Closing += delegate
            {
                Logger.Write("会话汇总  : 本次共移除 " + AppState.RemovedTotal + " 个设备");
            };
        }

        /// <summary>把版本号与真实权限状态写进窗口标题。</summary>
        static void ApplyWindowTitle()
        {
            AppState.Window.Title =
                "WindowsGhostDeviceCleanup_" + AppVersion + "（" + GetPermissionStatus() + "）";
        }

        /// <summary>返回当前进程的真实权限状态。清单声明了 requireAdministrator，正常情况下为"管理员"。</summary>
        public static string GetPermissionStatus()
        {
            try
            {
                var identity = WindowsIdentity.GetCurrent();
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator) ? "管理员" : "非管理员";
            }
            catch
            {
                return "未知";
            }
        }

        /// <summary>把无参方法包装成 ICommand，供快捷键绑定使用。</summary>
        class RelayCommand : ICommand
        {
            readonly Action _action;
            public RelayCommand(Action action) { _action = action; }
            public bool CanExecute(object p) { return true; }
            public void Execute(object p) { _action(); }
            public event EventHandler CanExecuteChanged { add { } remove { } }
        }

// 执行入口：扫描 / 移除 / 清空

        static void Scan()
        {
            // 防止重入：移除后的自动复扫可能与手动扫描撞车
            if (AppState.Busy)
            {
                Log("已有任务在执行，已忽略本次扫描请求。");
                Logger.Write("扫描请求被忽略（当前有任务在执行）");
                return;
            }

            SetBusy(true);
            AppState.BtnRemove.IsEnabled = false;
            AppState.BtnClear.IsEnabled = false;
            AppState.DeviceListPanel.Children.Clear();
            AppState.CheckBoxes.Clear();
            AppState.Devices.Clear();
            AppState.EmptyState.Visibility = Visibility.Collapsed;
            AppState.DeviceScroller.Visibility = Visibility.Visible;
            AppState.PageTitle.Text = "扫描结果";
            AppState.PageSubtitle.Text = "正在检测…";
            SetStatus("正在扫描系统…", "W32Sel");
            SetStatusBar("正在扫描…");
            SetProgress(0.08);
            Log("正在扫描…");
            Logger.Write("开始扫描");

            DeviceService.ScanAsync(OnScanDone, OnScanFailed);
        }

        static void OnScanFailed(string error)
        {
            SetStatus("扫描失败", "W32Red");
            SetStatusBar("扫描失败");
            AppState.PageSubtitle.Text = "扫描失败 — 详见日志";
            Log("错误：" + (string.IsNullOrEmpty(error) ? "<无错误消息，请用「选项 > 设备查询诊断」>" : error));
            SetBusy(false);
            SetProgress(0);
        }

        static void OnScanDone(ScanResult result)
        {
            AppState.Devices.AddRange(result.Devices);

            AppState.GhostCount.Text = result.GhostCount.ToString();
            AppState.ProtectedCount.Text = result.ProtectedCount.ToString();
            AppState.StatusBarCount.Text = "设备: " + result.Devices.Count +
                "（幽灵 " + result.GhostCount + " / 受保护 " + result.ProtectedCount + "）";

            if (result.Devices.Count == 0)
            {
                AppState.PageTitle.Text = "扫描结果";
                AppState.PageSubtitle.Text = "系统干净，未发现幽灵设备";
                AppState.EmptyState.Visibility = Visibility.Visible;
                AppState.DeviceScroller.Visibility = Visibility.Collapsed;
                SetStatus("系统干净", "W32Green");
                Log("系统干净。");
            }
            else
            {
                AppState.PageTitle.Text = "扫描结果";
                AppState.PageSubtitle.Text = "共 " + result.Devices.Count + " 个条目，耗时 " + result.ElapsedMs + " ms";
                RenderDeviceList();

                if (result.GhostCount == 0)
                {
                    SetStatus("发现受保护设备", "W32Orange");
                    Log("受保护：" + result.ProtectedCount + " — 如需移除请手动勾选。");
                }
                else
                {
                    SetStatus("幽灵设备：" + result.GhostCount, "W32Red");
                    Log("幽灵：" + result.GhostCount + "   受保护：" + result.ProtectedCount);
                }
                AppState.BtnRemove.IsEnabled = true;
            }

            AppState.BtnClear.IsEnabled = true;
            SetBusy(false);
            SetProgress(1.0);
            SetStatusBar("扫描完成，耗时 " + result.ElapsedMs + " ms");
            Log("扫描完成，耗时 " + result.ElapsedMs + " ms");
        }

        static void Remove()
        {
            // 勾选框与设备一一对应：渲染顺序 = 幽灵设备在前、受保护设备在后
            var selected = new List<DeviceItem>();
            var ordered = BuildOrderedList();
            for (int i = 0; i < ordered.Count && i < AppState.CheckBoxes.Count; i++)
                if (AppState.CheckBoxes[i].IsChecked == true) selected.Add(ordered[i]);

            if (selected.Count == 0) { Log("未选择设备。"); return; }

            int protectedSelected = selected.Count(delegate (DeviceItem x) { return x.IsProtected; });
            string msg = "确定要移除选中的 " + selected.Count + " 个设备吗？\n\n此操作无法撤销。";
            if (protectedSelected > 0)
                msg += "\n\n警告：其中 " + protectedSelected + " 个已配置 CPU 亲和性，\n移除将删除相应的 IRQ 绑定配置。";

            MessageBoxResult answer = MessageBox.Show(AppState.Window, msg, "确认移除",
                MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
            if (answer != MessageBoxResult.OK) { Log("已取消。"); return; }

            AppState.BtnRemove.IsEnabled = false;
            SetBusy(true);
            SetStatus("正在移除设备…", "W32Red");
            Log("正在移除 " + selected.Count + " 个设备…");

            DeviceService.RemoveAsync(selected, OnRemoveProgress, OnRemoveDone);
        }

        static void OnRemoveProgress(RemoveProgress p)
        {
            SetProgress((double)p.Done / p.Total);
            SetStatus("正在移除 " + p.Done + " / " + p.Total, "W32Red");
            SetStatusBar("移除中 " + p.Done + "/" + p.Total + "（成功 " + p.Ok + " 失败 " + p.Failed + "）");
        }

        static void OnRemoveDone(RemoveProgress p)
        {
            AppState.RemovedTotal += p.Ok;
            AppState.RemovedCount.Text = AppState.RemovedTotal.ToString();
            SetStatus("移除完成", "W32Green");
            Log("移除完成：成功 " + p.Ok + " 个，失败 " + p.Failed + " 个（会话累计 " + AppState.RemovedTotal + "）。正在重新扫描…");
            AppState.BtnScan.IsEnabled = true;
            SetBusy(false);
            Scan();
        }

        static void ClearAll()
        {
            AppState.DeviceListPanel.Children.Clear();
            AppState.CheckBoxes.Clear();
            AppState.Devices.Clear();
            AppState.EmptyState.Visibility = Visibility.Visible;
            AppState.DeviceScroller.Visibility = Visibility.Collapsed;
            AppState.GhostCount.Text = "—";
            AppState.ProtectedCount.Text = "—";
            AppState.BtnRemove.IsEnabled = false;
            AppState.BtnClear.IsEnabled = false;
            AppState.StatusBarCount.Text = "设备: 0";
            SetProgress(0);
            SetStatus("准备扫描", "W32Faint");
            SetStatusBar("已清空");
            Log("已清空。");
            Logger.Write("清空列表");
        }

        /// <summary>与 RenderDeviceList 的渲染顺序保持一致：幽灵在前，受保护在后。</summary>
        static List<DeviceItem> BuildOrderedList()
        {
            var res = new List<DeviceItem>();
            res.AddRange(AppState.Devices.Where(delegate (DeviceItem x) { return !x.IsProtected; }));
            res.AddRange(AppState.Devices.Where(delegate (DeviceItem x) { return x.IsProtected; }));
            return res;
        }

// 设备列表渲染

        static void RenderDeviceList()
        {
            if (AppState.Devices.Count == 0)
            {
                AppState.EmptyState.Visibility = Visibility.Visible;
                AppState.DeviceScroller.Visibility = Visibility.Collapsed;
                return;
            }

            AppState.EmptyState.Visibility = Visibility.Collapsed;
            AppState.DeviceScroller.Visibility = Visibility.Visible;
            AppState.DeviceListPanel.Children.Clear();
            AppState.CheckBoxes.Clear();

            var ghosts = AppState.Devices.Where(delegate (DeviceItem x) { return !x.IsProtected; }).ToList();
            var keep = AppState.Devices.Where(delegate (DeviceItem x) { return x.IsProtected; }).ToList();

            if (ghosts.Count > 0)
            {
                AddSectionHeader("可移除的幽灵设备（" + ghosts.Count + "）", "W32Red");
                foreach (var d in ghosts) AddDeviceRow(d);
            }

            if (keep.Count > 0)
            {
                if (ghosts.Count > 0) AddSeparator();
                AddSectionHeader("CPU 亲和性保护（" + keep.Count + "）", "W32Orange");
                foreach (var d in keep) AddDeviceRow(d);
            }
        }

        static void AddSectionHeader(string text, string colorKey)
        {
            AppState.DeviceListPanel.Children.Add(new TextBlock
            {
                Text = text,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Foreground = Res(colorKey),
                Margin = new Thickness(0, 4, 0, 7)
            });
        }

        static void AddSeparator()
        {
            AppState.DeviceListPanel.Children.Add(new Border
            {
                Height = 1,
                Background = Res("W32LineSoft"),
                Margin = new Thickness(0, 14, 0, 6)
            });
        }

        static void AddDeviceRow(DeviceItem d)
        {
            var row = new Border
            {
                Background = Brushes.Transparent,
                BorderBrush = Res("W32LineSoft"),
                BorderThickness = new Thickness(0, 0, 0, 1),
                Padding = new Thickness(4, 7, 4, 7),
                ToolTip = d.InstanceId
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };

            var cb = new CheckBox
            {
                Style = (Style)AppState.Window.FindResource("PlainCheck"),
                IsChecked = !d.IsProtected,
                Tag = d.IsProtected ? "PROTECTED::" + d.InstanceId : d.InstanceId
            };
            // 点击行的空白处也能切换勾选
            row.MouseLeftButtonDown += delegate (object s, MouseButtonEventArgs e)
            {
                if (e.OriginalSource is TextBlock || e.OriginalSource is Border)
                    cb.IsChecked = !(cb.IsChecked == true);
            };
            AppState.CheckBoxes.Add(cb);

            var dot = new Ellipse
            {
                Width = 7,
                Height = 7,
                Margin = new Thickness(0, 0, 9, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Fill = Res(d.IsProtected ? "W32Orange" : "W32Red")
            };

            var name = new TextBlock
            {
                Text = d.Name,
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Foreground = Res(d.IsProtected ? "W32Gray" : "W32Text")
            };

            sp.Children.Add(cb);
            sp.Children.Add(dot);
            sp.Children.Add(name);

            var badge = new Border
            {
                BorderThickness = new Thickness(1),
                Padding = new Thickness(7, 1, 7, 1),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(10, 0, 0, 0),
                BorderBrush = Res(d.IsProtected ? "W32Orange" : "W32Red"),
                Background = Brushes.Transparent
            };
            badge.Child = new TextBlock
            {
                Text = d.IsProtected ? "亲和性已配置" : "幽灵",
                FontSize = 11,
                Foreground = Res(d.IsProtected ? "W32Orange" : "W32Red")
            };
            Grid.SetColumn(badge, 1);

            grid.Children.Add(sp);
            grid.Children.Add(badge);
            row.Child = grid;

            AppState.DeviceListPanel.Children.Add(row);
        }

// 界面辅助

        static Brush Res(string key)
        {
            var b = AppState.Window.TryFindResource(key) as Brush;
            return b ?? Brushes.Gray;
        }

        static void Log(string message)
        {
            AppState.LogOutput.Text += "\n[" + DateTime.Now.ToString("HH:mm:ss") + "]  " + message;
            if (AppState.LogScroller != null) AppState.LogScroller.ScrollToBottom();
        }

        static void SetStatus(string text, string colorKey)
        {
            AppState.StatusLabel.Text = text;
            AppState.StatusDot.Fill = Res(colorKey);
        }

        static void SetStatusBar(string text) { AppState.StatusBarMain.Text = text; }

        static void SetProgress(double percent)
        {
            double width = 0;
            var parent = AppState.ProgressFill.Parent as Border;
            if (parent != null) width = parent.ActualWidth - 2;
            AppState.ProgressFill.Width = Math.Max(0, Math.Min(Math.Max(width, 0), width * percent));
        }

        static void SetBusy(bool busy)
        {
            AppState.Busy = busy;
            AppState.BtnScan.IsEnabled = !busy;
        }

        static void SelectAll(bool on)
        {
            foreach (var cb in AppState.CheckBoxes)
            {
                if (on && IsProtectedTag(cb)) continue;   // 受保护设备不参与"全选"
                cb.IsChecked = on;
            }
        }

        static bool IsProtectedTag(CheckBox cb)
        {
            string tag = cb.Tag as string;
            return tag != null && tag.StartsWith("PROTECTED::");
        }

        /// <summary>逐层探测设备查询链路，结果写入日志并弹窗显示。</summary>
        static void RunDiagnostics()
        {
            Log("正在执行设备查询诊断…");
            string report;
            try { report = WdcShell.Core.Probe.Run(); }
            catch (Exception ex) { report = "诊断本身失败: " + ex; }

            Logger.Write(report);
            MessageBox.Show(AppState.Window, report, "设备查询诊断",
                MessageBoxButton.OK, MessageBoxImage.Information);
            Log("诊断完成，结果已写入日志。");
        }

        /// <summary>在资源管理器中打开日志目录。</summary>
        static void OpenLogFolder()
        {
            try
            {
                System.IO.Directory.CreateDirectory(Logger.Directory);
                Process.Start("explorer.exe", "\"" + Logger.Directory + "\"");
                Log("已打开日志目录：" + Logger.Directory);
            }
            catch (Exception ex)
            {
                Log("无法打开日志目录：" + ex.Message);
            }
        }

        static void OpenProjectPage()
        {
            try { Process.Start("https://github.com/NeetheCheeBao/WinDeviceCleanup"); }
            catch (Exception ex) { Log("无法打开浏览器：" + ex.Message); }
        }
    }
}