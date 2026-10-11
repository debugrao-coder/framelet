#!/usr/bin/env python3
"""Source-level contracts/contrast only; cannot validate a Windows rendered UI."""
import hashlib,json,pathlib,re,xml.etree.ElementTree as ET
root=pathlib.Path(__file__).resolve().parents[1]
files={name:(root/name).read_text() for name in ['Theme.cs','App.xaml','App.xaml.cs','Launcher.cs','Editor.cs']}
checks=[]
def check(ok,label):
    assert ok,label
    checks.append(label)
theme=files['Theme.cs'];xaml=files['App.xaml'];editor=files['Editor.cs'];launcher=files['Launcher.cs']
ET.fromstring(xaml);check(True,'XAML is well-formed')
palette={name:(dark,light) for name,dark,light in re.findall(r'Set\("(\w+)", dark \? "(#[0-9A-F]+)" : "(#[0-9A-F]+)"\)',theme)}
def lum(value):
    rgb=[int(value[i:i+2],16)/255 for i in (1,3,5)]
    linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb]
    return sum(c*w for c,w in zip(linear,(.2126,.7152,.0722)))
ratios={}
for index,mode in enumerate(('dark','light')):
    for foreground,background in [('Label','WindowSurface'),('Label','GroupSurface'),('Label','ContentSurface'),('SecondaryLabel','WindowSurface'),('ControlLabel','ControlSurface'),('HoverLabel','HoverSurface'),('OnPrimary','PrimarySurface'),('DisabledLabel','ControlSurface')]:
        a,b=sorted((lum(palette[foreground][index]),lum(palette[background][index])))
        ratio=(b+.05)/(a+.05);ratios[f'{mode}:{foreground}/{background}']=round(ratio,2)
        check(ratio>=4.5,f'{mode} text pair {foreground}/{background} >= 4.5')
    for foreground,background in [('Focus','ControlSurface'),('Separator','GroupSurface')]:
        a,b=sorted((lum(palette[foreground][index]),lum(palette[background][index])))
        check((b+.05)/(a+.05)>=3,f'{mode} boundary {foreground}/{background} >= 3')
for key in palette:
    check(f'Set("{key}", SystemColors.' in theme,f'high contrast maps {key} to system brush')
for name in ('Editor.cs','Launcher.cs','App.xaml'):
    check(not any(old in files[name] for old in ('#F7F5EF','#DDF275','#EEECE5','Color.FromRgb(34, 43, 44)','Color.FromRgb(221, 242, 117)','Color.FromRgb(229, 228, 219)')),name+' has no legacy chrome palette')
check('SystemFonts.MessageFontFamilyKey' in xaml,'font owned by Windows')
check('ColorValuesChanged +=' in theme and 'ColorValuesChanged -=' in theme,'theme subscription released')
check('StaticPropertyChanged +=' in theme and 'StaticPropertyChanged -=' in theme,'high contrast subscription released')
check('Dispatcher.BeginInvoke' in theme,'theme event dispatched to UI thread')
check('SystemParameters.HighContrast' in theme,'high contrast wins over ordinary palette')
check('Theme.Group(actions)' in launcher and 'Theme.Group(commands)' in editor and 'Theme.Group(left)' in editor,'shared rounded command groups')
check('Theme.Bind(ocrPane, Border.BackgroundProperty, "GroupSurface")' in editor,'OCR follows same appearance')
check('canvas.Background = Brushes.White' in editor and 'Brushes.OrangeRed' in editor and 'Brushes.Black' in editor,'capture canvas and annotation colors not theme-bound')
check(not any(effect in launcher+editor+xaml for effect in ('BlurEffect','DropShadowEffect','AllowsTransparency','Opacity="0.')), 'no glass blur or opacity layered onto content')
check('if (saving || recognizing || canvas.IsMouseCaptured) return;' in editor and 'snapshot.IsFrozen' in editor and 'AtomicFileSave.Save' in editor,'save safety guards retained')
check('if (saving) { e.Cancel = true;' in editor,'busy-close guard retained')
check('IsKeyboardFocused' in xaml and 'IsEnabled' in xaml and 'IsPressed' in xaml,'focus disabled pressed control states present')
check('SystemColors.HighlightTextBrushKey' in xaml,'native selection pairs use system contrast colors')
check('Appearance?.Dispose()' in files['App.xaml.cs'],'theme lifecycle closed with app')
check('SF Pro' not in ''.join(files.values()) and 'San Francisco' not in ''.join(files.values()),'no Apple font copy')
print(json.dumps({'status':'PASS_SCOPED','assertions':len(checks),'scope':'source contracts and authored palette contrast; NOT rendered Windows visual/accessibility evidence','checks':checks,'contrast_ratios':ratios,'source_sha256':{name:hashlib.sha256(text.encode()).hexdigest() for name,text in files.items()}},indent=2))
