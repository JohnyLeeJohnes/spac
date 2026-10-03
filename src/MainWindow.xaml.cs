using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace Spac;

public partial class MainWindow : Window
{
    private const int MaxHours = 23, MaxMinutes = 59;

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly bool _ready;
    private bool _rendering;

    // Co si uživatel naklikal; zobrazený stav přepínačů se z toho odvozuje podle zvolené akce.
    private bool _force, _hybrid, _restore;
    private Countdown? _countdown;
    private string? _notice;
    private bool _noticeIsError;

    public MainWindow()
    {
        InitializeComponent();
        _ready = true;

        if (!Shutdown.CanHibernate)
        {
            HibernateTile.IsEnabled = false;
            HibernateTile.ToolTip = "Hibernace je na tomhle počítači vypnutá.";
        }

        _countdown = Countdown.Load();
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
        Render();
    }

    private PowerAction Action =>
        RestartTile.IsChecked == true ? PowerAction.Restart :
        HibernateTile.IsChecked == true ? PowerAction.Hibernate :
        LogOffTile.IsChecked == true ? PowerAction.LogOff :
        PowerAction.Shutdown;

    private int Minutes => Read(HoursBox) * 60 + Read(MinutesBox);

    private string Arguments
    {
        get
        {
            var action = Action;
            bool force = _force || Shutdown.TimedByWindows(action);
            return Shutdown.Arguments(action, Minutes * 60, force, _hybrid, _restore);
        }
    }

    private int Read(TextBox box) =>
        int.TryParse(box.Text, out int value) ? Math.Min(value, box == HoursBox ? MaxHours : MaxMinutes) : 0;

    private void Write(TextBox box, int value) =>
        box.Text = value.ToString(box == HoursBox ? "0" : "00");

    private static (string Noun, string Accusative, string Sentence) Words(PowerAction action) => action switch
    {
        PowerAction.Restart => ("Restart", "restart", "Počítač se restartuje"),
        PowerAction.Hibernate => ("Hibernace", "hibernaci", "Počítač přejde do hibernace"),
        PowerAction.LogOff => ("Odhlášení", "odhlášení", "Odhlášení proběhne"),
        _ => ("Vypnutí", "vypnutí", "Počítač se vypne"),
    };

    // "ve 23:45", "v 1:05", "zítra ve 2:30"
    private static string At(DateTime local)
    {
        string day = local.Date == DateTime.Today ? "" : "zítra ";
        string preposition = local.Hour is 2 or 3 or 4 or 12 or 13 or 14 or >= 20 ? "ve" : "v";
        return $"{day}{preposition} {local:H:mm}";
    }

    // ---- Vykreslení ----

    private void Render()
    {
        if (!_ready) return;

        bool running = _countdown != null;
        FormView.Visibility = running ? Visibility.Hidden : Visibility.Visible;
        FormView.IsEnabled = !running;
        RunView.Visibility = running ? Visibility.Visible : Visibility.Hidden;

        if (running) RenderCountdown();
        else RenderForm();
    }

    private void RenderForm()
    {
        var action = Action;
        bool timed = Shutdown.TimedByWindows(action);
        int minutes = Minutes;

        // Nastavování IsChecked níže vyvolá Checked/Unchecked; ty se během vykreslení ignorují.
        _rendering = true;
        ForceToggle.IsEnabled = !timed;
        ForceToggle.IsChecked = timed || _force;
        HybridToggle.IsEnabled = action == PowerAction.Shutdown;
        HybridToggle.IsChecked = HybridToggle.IsEnabled && _hybrid;
        RestoreToggle.IsEnabled = timed;
        RestoreToggle.IsChecked = timed && _restore;
        RestoreFlag.Text = action == PowerAction.Restart ? "/g" : "/sg";

        foreach (var chip in Presets.Children.OfType<RadioButton>())
            chip.IsChecked = (string)chip.Tag == minutes.ToString();
        _rendering = false;

        CommandText.Text = "shutdown " + Arguments;
        StartButton.Content = "Naplánovat " + Words(action).Accusative;
        StartButton.IsEnabled = minutes > 0;
        RenderWhen();

        StatusText.Foreground = (Brush)FindResource(_notice == null ? "Muted" : _noticeIsError ? "Danger" : "Text");
        StatusText.Text = _notice ?? (timed
            ? "Odpočet hlídá Windows, Spáče pak můžeš zavřít."
            : "Odpočet hlídá Spáč, nech ho běžet na pozadí.");
    }

    private void RenderWhen()
    {
        int minutes = Minutes;
        WhenText.Text = minutes > 0
            ? $"{Words(Action).Sentence} {At(DateTime.Now.AddMinutes(minutes))}"
            : "Nastav aspoň jednu minutu.";
    }

    private void RenderCountdown()
    {
        var countdown = _countdown!;
        double left = Math.Max(0, (countdown.Due - DateTime.UtcNow).TotalSeconds);
        var shown = TimeSpan.FromSeconds(Math.Ceiling(left));

        RunTitle.Text = Words(countdown.Action).Noun.ToUpper() + " ZA";
        CountdownText.Text = shown.ToString(shown.TotalHours >= 1 ? @"h\:mm\:ss" : @"mm\:ss");
        RunWhen.Text = At(countdown.Due.ToLocalTime());
        RunCommand.Text = "shutdown " + countdown.Arguments;

        double fraction = Math.Min(1, left / countdown.Seconds);
        BarLeft.Width = new GridLength(fraction, GridUnitType.Star);
        BarGone.Width = new GridLength(1 - fraction, GridUnitType.Star);

        if (_notice == null)
        {
            RunStatus.Foreground = (Brush)FindResource("Muted");
            RunStatus.Text = countdown.TimedByWindows
                ? "Odpočet hlídá Windows, Spáče můžeš klidně zavřít."
                : "Odpočet hlídá Spáč. Nech ho běžet, zavřením okna ho zrušíš.";
        }
    }

    private void Notify(string text, bool error)
    {
        _notice = text;
        _noticeIsError = error;
        if (_countdown != null)
        {
            RunStatus.Foreground = (Brush)FindResource("Danger");
            RunStatus.Text = text;
        }
        Render();
    }

    private void Fail((int Code, string Message) result) => Notify(
        result.Message.Length > 0 ? result.Message : $"shutdown.exe skončil s chybou {result.Code}.", error: true);

    // ---- Odpočet ----

    private void Tick()
    {
        if (_countdown == null)
        {
            RenderWhen();
            return;
        }

        if (_countdown.Due > DateTime.UtcNow)
        {
            RenderCountdown();
            return;
        }

        var due = _countdown;
        Stop();
        if (!due.TimedByWindows)
        {
            var result = Shutdown.Run(due.Arguments);
            if (result.Code != 0) Fail(result);
        }
    }

    private void Stop()
    {
        Countdown.Clear();
        _countdown = null;
        _notice = null;
        Render();
    }

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        if (_countdown != null || Minutes == 0) return;

        var countdown = new Countdown { Action = Action, Seconds = Minutes * 60, Arguments = Arguments };
        if (countdown.TimedByWindows)
        {
            var result = Shutdown.Run(countdown.Arguments);
            if (result.Code == Shutdown.AlreadyScheduled)
            {
                // Už něco naplánovaného je (třeba z příkazové řádky): nové nastavení ho nahradí.
                Shutdown.Run("/a");
                result = Shutdown.Run(countdown.Arguments);
            }
            if (result.Code != 0)
            {
                Fail(result);
                return;
            }
        }

        countdown.Due = DateTime.UtcNow.AddSeconds(countdown.Seconds);
        if (countdown.TimedByWindows) countdown.Save();
        _countdown = countdown;
        _notice = null;
        Render();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (_countdown == null) return;

        if (_countdown.TimedByWindows)
        {
            var result = Shutdown.Run("/a");
            if (result.Code != 0 && result.Code != Shutdown.NothingScheduled)
            {
                Fail(result);
                return;
            }
        }
        Stop();
    }

    // Zruší cokoli, co je ve Windows naplánované, i když to nenastavil Spáč.
    private void Abort_Click(object sender, RoutedEventArgs e)
    {
        var result = Shutdown.Run("/a");
        if (result.Code == 0) Notify("Naplánované vypnutí je zrušené.", error: false);
        else if (result.Code == Shutdown.NothingScheduled) Notify("Nic naplánovaného není, není co rušit.", error: false);
        else Fail(result);
    }

    // ---- Formulář ----

    private void Changed()
    {
        _notice = null;
        Render();
    }

    private void Action_Changed(object sender, RoutedEventArgs e) => Changed();

    private void Toggle_Changed(object sender, RoutedEventArgs e)
    {
        if (_rendering) return;

        bool on = ((CheckBox)sender).IsChecked == true;
        if (sender == ForceToggle) _force = on;
        else if (sender == HybridToggle) _hybrid = on;
        else _restore = on;

        // shutdown.exe kombinaci /sg /hybrid nebere, takže zapnutí jednoho vypne druhé.
        if (on && sender == HybridToggle) _restore = false;
        if (on && sender == RestoreToggle) _hybrid = false;
        Changed();
    }

    private void Preset_Checked(object sender, RoutedEventArgs e)
    {
        if (_rendering) return;

        int minutes = int.Parse((string)((RadioButton)sender).Tag);
        Write(HoursBox, minutes / 60);
        Write(MinutesBox, minutes % 60);
        Changed();
    }

    private void Time_Changed(object sender, TextChangedEventArgs e)
    {
        var box = (TextBox)sender;
        string digits = new(box.Text.Where(c => c is >= '0' and <= '9').ToArray());
        if (digits != box.Text)
        {
            box.Text = digits;
            box.CaretIndex = digits.Length;
            return;
        }
        Changed();
    }

    private void Time_LostFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        var box = (TextBox)sender;
        Write(box, Read(box));
    }

    private void Time_GotFocus(object sender, KeyboardFocusChangedEventArgs e) => ((TextBox)sender).SelectAll();

    // Bez tohohle by první klik myší označení z GotFocus hned zase zrušil.
    private void Time_MouseDown(object sender, MouseButtonEventArgs e)
    {
        var box = (TextBox)sender;
        if (box.IsKeyboardFocusWithin) return;
        box.Focus();
        e.Handled = true;
    }

    private void Time_Wheel(object sender, MouseWheelEventArgs e)
    {
        var box = (TextBox)sender;
        Nudge(box, Math.Sign(e.Delta) * (box == HoursBox ? 1 : 5));
        e.Handled = true;
    }

    private void Time_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Up && e.Key != Key.Down) return;
        Nudge((TextBox)sender, e.Key == Key.Up ? 1 : -1);
        e.Handled = true;
    }

    private void Nudge(TextBox box, int delta)
    {
        int max = box == HoursBox ? MaxHours : MaxMinutes;
        Write(box, Math.Max(0, Math.Min(max, Read(box) + delta)));
        box.SelectAll();
    }

    // ---- Tmavý titulkový pruh ----

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        IntPtr hwnd = new WindowInteropHelper(this).Handle;

        const int UseImmersiveDarkMode = 20, BorderColor = 34, CaptionColor = 35;
        int on = 1;
        int bg = 0x0022140F; // #0F1422 jako COLORREF (0x00BBGGRR)

        // Na starších Windows volání jen vrátí chybu a pruh zůstane výchozí.
        DwmSetWindowAttribute(hwnd, UseImmersiveDarkMode, ref on, sizeof(int));
        DwmSetWindowAttribute(hwnd, CaptionColor, ref bg, sizeof(int));
        DwmSetWindowAttribute(hwnd, BorderColor, ref bg, sizeof(int));
    }
}
