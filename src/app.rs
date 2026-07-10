use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::rc::Rc;
use std::sync::{mpsc, Arc, Mutex};

use chrono::{DateTime, Utc};
use gtk4::prelude::*;
use gtk4::{gdk, glib};
use libadwaita as adw;
use ksni::TrayMethods;
use lru::LruCache;
use url::Url;

use crate::client::ApiClient;
use crate::models::{Notification, NotificationsPage};
use crate::settings::Settings;

type ImageCache = Arc<Mutex<LruCache<String, Vec<u8>>>>;

const DEFAULT_SERVER: &str = "http://localhost:7777";
const PAGE_COUNT: u32 = 80;

struct TrayState {
    unread: Arc<Mutex<u32>>,
    total: Arc<Mutex<u32>>,
    toggle_tx: mpsc::Sender<()>,
}

impl ksni::Tray for TrayState {
    fn id(&self) -> String { "ml.rawdog.xnotifs".into() }
    fn title(&self) -> String { "X Notifications".into() }
    fn tool_tip(&self) -> ksni::ToolTip {
        let unread = *self.unread.lock().unwrap();
        let total = *self.total.lock().unwrap();
        let text = if unread > 0 {
            format!("{} new — {} total", unread, total)
        } else if total > 0 {
            format!("{} notifications", total)
        } else {
            "X Notifications — all caught up".into()
        };
        ksni::ToolTip { title: "X Notifications".into(), description: text, icon_name: "".into(), icon_pixmap: vec![] }
    }
    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        vec![make_tray_icon(*self.unread.lock().unwrap())]
    }
    fn activate(&mut self, _x: i32, _y: i32) { let _ = self.toggle_tx.send(()); }
    fn category(&self) -> ksni::Category { ksni::Category::ApplicationStatus }
    fn status(&self) -> ksni::Status { ksni::Status::Active }
}

fn make_tray_icon(count: u32) -> ksni::Icon {
    let size: u32 = 48;
    let mut pixels = vec![0u8; (size * size * 4) as usize];
    let cx = (size / 2) as i32;
    let cy = (size / 2) as i32;
    let radius = (size / 2 - 4) as i32;

    let (cr, cg, cb): (u8, u8, u8) = if count == 0 {
        (29, 155, 240)
    } else if count < 10 {
        (255, 165, 0)
    } else {
        (255, 59, 48)
    };

    for y in 0..size as i32 {
        for x in 0..size as i32 {
            let dx = x - cx; let dy = y - cy;
            let dist2 = dx * dx + dy * dy;
            let idx = ((y as u32 * size + x as u32) * 4) as usize;
            if dist2 <= radius * radius {
                pixels[idx]=cr; pixels[idx+1]=cg; pixels[idx+2]=cb; pixels[idx+3]=255;
            } else if dist2 <= (radius + 2) * (radius + 2) {
                let t = dist2 - radius * radius;
                let d = (radius + 2) * (radius + 2) - radius * radius;
                let v = ((d - t) as f64 / d as f64 * 128.0) as u8;
                pixels[idx]=cr; pixels[idx+1]=cg; pixels[idx+2]=cb; pixels[idx+3]=v;
            }
        }
    }

    let mut argb = vec![0u8; pixels.len()];
    for i in 0..(pixels.len() / 4) {
        let j = i * 4; argb[j]=pixels[j+3]; argb[j+1]=pixels[j]; argb[j+2]=pixels[j+1]; argb[j+3]=pixels[j+2];
    }
    ksni::Icon { width: size as i32, height: size as i32, data: argb }
}
fn actor_names(notif: &Notification) -> String {
    match notif.actors.first() {
        None => "Someone".to_string(),
        Some(actor) => {
            if notif.others_count.unwrap_or(0) > 0 {
                format!("{} and {} others", actor.name, notif.others_count.unwrap_or(0))
            } else if notif.actors.len() > 1 {
                format!("{} and {} others", actor.name, notif.actors.len() - 1)
            } else { actor.name.clone() }
        }
    }
}

fn kind_border_color(kind: &str) -> &'static str {
    match kind {
        "like"=>"#f91880","retweet"=>"#00ba7c","reply"=>"#1d9bf0",
        "quote"=>"#1d9bf0","follow"=>"#1d9bf0","mention"=>"#1d9bf0",_=>"#8b98a5",
    }
}

fn notif_icon_name(kind: &str) -> &'static str {
    match kind {
        "like"=>"love-symbolic","retweet"=>"view-refresh-symbolic",
        "reply"=>"mail-replied-symbolic","quote"=>"format-indent-more-symbolic",
        "follow"=>"contact-new-symbolic","mention"=>"user-available-symbolic",
        _=>"dialog-information-symbolic",
    }
}

fn relative_time(timestamp: &DateTime<Utc>) -> String {
    let secs = Utc::now().signed_duration_since(*timestamp).num_seconds();
    if secs < 0 { "now".into() }
    else if secs < 60 { format!("{secs}s") }
    else if secs < 3600 { format!("{}m", secs / 60) }
    else if secs < 86400 { format!("{}h", secs / 3600) }
    else { timestamp.format("%b %-d").to_string() }
}

fn format_count(n: u64) -> String {
    if n >= 1_000_000 { format!("{:.1}M", n as f64 / 1_000_000.0) }
    else if n >= 1_000 { format!("{:.1}K", n as f64 / 1_000.0) }
    else { n.to_string() }
}

fn build_notification_row(notif: &Notification, image_cache: &ImageCache, list_box: &gtk4::ListBox, settings: &Settings) {
    #[allow(deprecated)]
    {
    let row = gtk4::ListBoxRow::new();
    row.add_css_class("notif-row");
    let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
    let border = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    border.set_size_request(3, -1);
    let bc = format!(".notif-border {{ background-color: {}; }}", kind_border_color(&notif.kind));
    let bp = gtk4::CssProvider::new(); bp.load_from_string(&bc);
    border.style_context().add_provider(&bp, gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION);
    row_box.append(&border);
    let card = gtk4::Box::new(gtk4::Orientation::Horizontal, 12);
    card.set_margin_start(12); card.set_margin_end(14); card.set_margin_top(9); card.set_margin_bottom(9);
    let avatar = adw::Avatar::new(38, None::<&str>, true);
    avatar.add_css_class("notif-avatar");
    if let Some(actor) = notif.actors.first() {
        avatar.set_text(Some(&actor.name));
        if let Some(ref url) = actor.avatar_url { load_avatar(&avatar, url, image_cache); }
    }
    card.append(&avatar);
    let content_col = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
    content_col.set_hexpand(true);
    let name_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
    let name_label = gtk4::Label::new(None);
    name_label.set_markup(&format!("<span weight=\"bold\">{}</span>", glib::markup_escape_text(&actor_names(notif))));
    name_label.set_halign(gtk4::Align::Start); name_label.add_css_class("notif-name");
    name_label.set_ellipsize(gtk4::pango::EllipsizeMode::End);
    name_row.append(&name_label);
    if notif.actors.first().map(|a| a.verified).unwrap_or(false) {
        let v = gtk4::Image::from_icon_name("emblem-ok-symbolic"); v.set_pixel_size(14); v.add_css_class("verified-badge"); name_row.append(&v);
    }
    let spacer = gtk4::Label::new(None); spacer.set_hexpand(true); name_row.append(&spacer);
    let time_label = gtk4::Label::new(Some(&relative_time(&notif.timestamp)));
    time_label.add_css_class("notif-time"); name_row.append(&time_label);
    content_col.append(&name_row);
    let kind_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 4);
    let type_icon = gtk4::Image::from_icon_name(notif_icon_name(&notif.kind));
    type_icon.set_pixel_size(12); type_icon.add_css_class("notif-type-icon"); kind_row.append(&type_icon);
    if notif.kind == "follow" || notif.kind == "mention" {
        if let Some(handle) = notif.actors.first().map(|a| a.handle.as_str()) {
            let hl = gtk4::Label::new(None);
            hl.set_markup(&format!("<span size=\"x-small\" foreground=\"#71767b\">@{}</span>", glib::markup_escape_text(handle)));
            hl.set_ellipsize(gtk4::pango::EllipsizeMode::End); kind_row.append(&hl);
        }
    }
    content_col.append(&kind_row);
    if let Some(ref snippet) = notif.target_tweet_snippet {
        let body = gtk4::Label::new(Some(snippet));
        body.set_wrap(true); body.set_wrap_mode(gtk4::pango::WrapMode::WordChar);
        body.set_lines(2); body.set_ellipsize(gtk4::pango::EllipsizeMode::End);
        body.set_xalign(0.0); body.add_css_class("notif-snippet"); content_col.append(&body);
    }
    let meta_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    if let Some(count) = notif.target_tweet_like_count {
        if count > 0 {
            let likes = gtk4::Label::new(None);
            likes.set_markup(&format!("<span size=\"x-small\" foreground=\"#71767b\">{} likes</span>", format_count(count)));
            meta_row.append(&likes);
        }
    }
    content_col.append(&meta_row);
    card.append(&content_col);
    if settings.show_thumbnails {
        if let Some(media) = notif.target_media.first() {
            let tf = gtk4::Frame::new(None::<&str>); tf.add_css_class("notif-thumb-frame");
            let thumb = gtk4::Picture::new(); thumb.set_size_request(48, 48);
            thumb.add_css_class("notif-thumb"); thumb.set_content_fit(gtk4::ContentFit::Cover);
            tf.set_child(Some(&thumb)); load_thumbnail(&thumb, &media.url, image_cache); card.append(&tf);
        }
    }
    row_box.append(&card); row.set_child(Some(&row_box));
    list_box.append(&row);
    } // allow(deprecated)
}

fn open_notification(notif: &Notification) {
    let url = if let Some(ref tid) = notif.target_tweet_id { format!("https://x.com/i/web/status/{tid}") }
    else if let Some(ref a) = notif.actors.first() { format!("https://x.com/{}", a.handle) }
    else { "https://x.com/notifications".into() };
    let _ = open::that_detached(&url);
}

fn fetch_image_bytes(url: &str, cache: &ImageCache) -> Option<Vec<u8>> {
    if let Some(b) = cache.lock().unwrap().get(url) { return Some(b.clone()); }
    let resp = reqwest::blocking::get(url).ok()?;
    let bytes = resp.bytes().ok()?.to_vec();
    cache.lock().unwrap().put(url.to_string(), bytes.clone());
    Some(bytes)
}
fn load_avatar(a: &adw::Avatar, url: &str, cache: &ImageCache) {
    if let Some(b) = fetch_image_bytes(url, cache) {
        if let Ok(t) = gdk::Texture::from_bytes(&glib::Bytes::from(&b)) { a.set_custom_image(Some(&t)); }
    }
}
fn load_thumbnail(p: &gtk4::Picture, url: &str, cache: &ImageCache) {
    if let Some(b) = fetch_image_bytes(url, cache) {
        if let Ok(t) = gdk::Texture::from_bytes(&glib::Bytes::from(&b)) { p.set_paintable(Some(&t)); }
    }
}
fn rebuild_list(lb: &gtk4::ListBox, notifs: &[Notification], ic: &ImageCache, s: &Settings) {
    while let Some(row) = lb.first_child() { lb.remove(&row); }
    for n in notifs.iter() { build_notification_row(n, ic, lb, s); }
}

fn make_css(scale: f64) -> String {
    format!(".xnotifs-window {{ font-size: {}%; }}\n{}", (scale * 100.0) as i32, include_str!("style.css"))
}

fn show_settings_dialog(parent: &gtk4::ApplicationWindow, settings: Rc<RefCell<Settings>>, css_provider: gtk4::CssProvider, window: gtk4::ApplicationWindow) {
    let dialog = gtk4::Dialog::builder()
        .title("Settings").transient_for(parent).modal(true)
        .default_width(380).default_height(420)
        .build();
    dialog.add_button("Cancel", gtk4::ResponseType::Cancel);
    dialog.add_button("Save", gtk4::ResponseType::Apply);

    let content = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    content.set_margin_start(20); content.set_margin_end(20); content.set_margin_top(16); content.set_margin_bottom(8);
    dialog.content_area().append(&content);

    let s = settings.borrow();

    let font_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let font_label = gtk4::Label::new(Some("Font scale"));
    font_label.set_halign(gtk4::Align::Start); font_label.set_hexpand(true);
    font_box.append(&font_label);
    let font_dropdown = gtk4::DropDown::from_strings(&["Small (0.85)", "Default (1.0)", "Large (1.15)", "X-Large (1.3)"]);
    font_dropdown.set_selected(match s.font_scale { x if x<0.95=>0, x if x<1.05=>1, x if x<1.2=>2, _=>3 });
    font_box.append(&font_dropdown);
    content.append(&font_box);

    let thumb_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let thumb_label = gtk4::Label::new(Some("Show thumbnails"));
    thumb_label.set_halign(gtk4::Align::Start); thumb_label.set_hexpand(true);
    thumb_box.append(&thumb_label);
    let thumb_switch = gtk4::Switch::new();
    thumb_switch.set_active(s.show_thumbnails); thumb_switch.set_valign(gtk4::Align::Center);
    thumb_box.append(&thumb_switch);
    content.append(&thumb_box);

    let w_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    w_box.append(&gtk4::Label::new(Some("Width")));
    let w_spin = gtk4::SpinButton::new(Some(&gtk4::Adjustment::new(s.window_width as f64, 320.0, 1400.0, 10.0, 40.0, 0.0)), 10.0, 0);
    w_box.append(&w_spin);
    content.append(&w_box);

    let h_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    h_box.append(&gtk4::Label::new(Some("Height")));
    let h_spin = gtk4::SpinButton::new(Some(&gtk4::Adjustment::new(s.window_height as f64, 400.0, 2000.0, 10.0, 40.0, 0.0)), 10.0, 0);
    h_box.append(&h_spin);
    content.append(&h_box);

    let poll_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    poll_box.append(&gtk4::Label::new(Some("Poll (seconds)")));
    let poll_spin = gtk4::SpinButton::new(Some(&gtk4::Adjustment::new(s.poll_interval_secs as f64, 5.0, 300.0, 5.0, 15.0, 0.0)), 5.0, 0);
    poll_box.append(&poll_spin);
    content.append(&poll_box);

    drop(s);

    dialog.connect_response(move |_, response| {
        if response == gtk4::ResponseType::Apply {
            let mut s = settings.borrow_mut();
            s.font_scale = match font_dropdown.selected() { 0=>0.85, 2=>1.15, 3=>1.3, _=>1.0 };
            s.show_thumbnails = thumb_switch.is_active();
            s.window_width = w_spin.value() as i32; s.window_height = h_spin.value() as i32;
            s.poll_interval_secs = poll_spin.value() as u64;
            s.save();
            let css = make_css(s.font_scale); css_provider.load_from_string(&css);
            window.set_default_size(s.window_width, s.window_height);
        }
    });

    dialog.present();
}

pub fn run() {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "xnotifs=info".into())).init();
    let app = adw::Application::builder().application_id("ml.rawdog.xnotifs").build();
    app.connect_activate(build_ui);
    app.run_with_args::<&str>(&[]);
}

fn build_ui(app: &adw::Application) {
    let settings = Rc::new(RefCell::new(Settings::load()));
    let server_url; let api; let mut window_width; let mut window_height; let poll_interval;
    {
        let s = settings.borrow();
        server_url = if s.server_url.is_empty() { std::env::var("XNOTIFS_SERVER").unwrap_or_else(|_| DEFAULT_SERVER.to_string()) } else { s.server_url.clone() };
        window_width = s.window_width; window_height = s.window_height; poll_interval = s.poll_interval_secs;
    }

    let css = make_css(settings.borrow().font_scale);
    let css_provider = gtk4::CssProvider::new(); css_provider.load_from_string(&css);
    gtk4::style_context_add_provider_for_display(&gdk::Display::default().expect("display"), &css_provider, gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION);

    api = ApiClient::new(Url::parse(&server_url).expect("valid URL"));

    let notifications: Rc<RefCell<Vec<Notification>>> = Rc::new(RefCell::new(Vec::new()));
    let seen_ids: Rc<RefCell<HashSet<String>>> = Rc::new(RefCell::new(HashSet::new()));
    let image_cache: ImageCache = Arc::new(Mutex::new(LruCache::new(std::num::NonZeroUsize::new(256).unwrap())));
    let unread = Arc::new(Mutex::new(0u32)); let total = Arc::new(Mutex::new(0u32));
    let next_cursor: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
    let loading_more: Rc<Cell<bool>> = Rc::new(Cell::new(false));
    let (toggle_tx, toggle_rx) = mpsc::channel();

    let tray = TrayState { unread: Arc::clone(&unread), total: Arc::clone(&total), toggle_tx };
    let rt = Box::leak(Box::new(tokio::runtime::Runtime::new().expect("tokio")));
    rt.spawn(async move {
        match tray.spawn().await {
            Ok(_) => { tracing::info!("KDE tray icon registered"); std::future::pending::<()>().await; }
            Err(e) => { tracing::error!("Failed to register tray icon: {e}"); }
        }
    });

    let window = gtk4::ApplicationWindow::new(app);
    window.set_title(Some("X Notifications"));
    window.set_decorated(true); window.set_resizable(true);
    window.set_default_size(window_width, window_height);
    window.set_hide_on_close(true); window.add_css_class("xnotifs-window");

    {
        window.connect_close_request(move |w| { w.set_visible(false); glib::Propagation::Stop });
    }

    let main_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    let header = adw::HeaderBar::new(); header.add_css_class("flat");
    let title_widget = gtk4::Label::new(Some("X Notifications")); title_widget.add_css_class("panel-title");
    header.set_title_widget(Some(&title_widget));
    let settings_btn = gtk4::Button::from_icon_name("emblem-system-symbolic"); settings_btn.set_tooltip_text(Some("Settings"));

    {
        let s = settings.clone(); let p = css_provider.clone(); let w = window.clone();
        settings_btn.connect_clicked(move |_| show_settings_dialog(&w, s.clone(), p.clone(), w.clone()));
    }

    header.pack_start(&settings_btn);
    let refresh_btn = gtk4::Button::from_icon_name("view-refresh-symbolic"); refresh_btn.set_tooltip_text(Some("Refresh"));
    header.pack_end(&refresh_btn);
    main_box.append(&header);

    let scrolled = gtk4::ScrolledWindow::new();
    scrolled.set_vexpand(true); scrolled.set_policy(gtk4::PolicyType::Never, gtk4::PolicyType::Automatic);
    let list_box = gtk4::ListBox::new(); list_box.add_css_class("notif-list"); list_box.set_selection_mode(gtk4::SelectionMode::Single);
    scrolled.set_child(Some(&list_box)); main_box.append(&scrolled);

    {
        let lb = list_box.clone();
        let n = notifications.clone();
        lb.connect_row_activated(move |_, row| {
            let idx = row.index() as usize;
            if let Some(notif) = n.borrow().get(idx) {
                open_notification(notif);
            }
        });
    }

    let empty_page = adw::StatusPage::new();
    empty_page.set_icon_name(Some("dialog-information-symbolic"));
    empty_page.set_title("Loading..."); empty_page.set_description(Some("Fetching notifications..."));
    list_box.set_placeholder(Some(&empty_page));
    window.set_child(Some(&main_box));

    let key_controller = gtk4::EventControllerKey::new();
    {
        let w = window.clone();
        key_controller.connect_key_pressed(move |_, key, _, m| {
            if key == gdk::Key::Escape && m.is_empty() { w.set_visible(false); return glib::Propagation::Stop; }
            glib::Propagation::Proceed
        });
    }
    window.add_controller(key_controller);

    let (poll_tx, poll_rx): (mpsc::Sender<Result<NotificationsPage, String>>, _) = mpsc::channel();

    {
        let a = api.clone(); let tx = poll_tx.clone();
        let n = notifications.clone(); let lb = list_box.clone(); let ic = Arc::clone(&image_cache); let s = settings.clone();
        refresh_btn.connect_clicked(move |_| {
            n.borrow_mut().clear();
            rebuild_list(&lb, &[], &ic, &s.borrow());
            let a = a.clone(); let tx = tx.clone();
            std::thread::spawn(move || { let _ = tx.send(a.notifications(None, PAGE_COUNT).map_err(|e| e.to_string())); });
        });
    }

    {
        let vadj = scrolled.vadjustment(); let a = api.clone(); let tx = poll_tx.clone();
        let nc = next_cursor.clone(); let lm = loading_more.clone();
        vadj.connect_value_changed(move |adj| {
            if adj.upper() - (adj.value() + adj.page_size()) < 200.0 && !lm.get() {
                if let Some(ref c) = *nc.borrow() { lm.set(true);
                    let a = a.clone(); let tx = tx.clone(); let c = c.clone();
                    std::thread::spawn(move || { let _ = tx.send(a.notifications(Some(&c), PAGE_COUNT).map_err(|e| e.to_string())); });
                }
            }
        });
    }

    let settings_rc = settings.clone();
    {
        let n = notifications.clone(); let si = seen_ids.clone(); let lb = list_box.clone();
        let ic = Arc::clone(&image_cache); let ur = Arc::clone(&unread); let to = Arc::clone(&total);
        let nc = next_cursor.clone(); let lm = loading_more.clone(); let ep = empty_page.clone();
        let s = settings.clone();
        glib::idle_add_local(move || {
            while let Ok(result) = poll_rx.try_recv() {
                lm.set(false);
                match result {
                    Ok(page) => {
                        *nc.borrow_mut() = page.cursor;
                        let nitems = page.notifications.len();
                        let mut new_count = 0u32;
                        for notif in &page.notifications {
                            if si.borrow_mut().insert(notif.id.clone()) { new_count += 1; }
                        }
                        let mut all = n.borrow_mut();
                        let existing_ids: HashSet<_> = all.iter().map(|n| n.id.clone()).collect();
                        let mut insert_idx = 0usize;
                        for notif in page.notifications {
                            if !existing_ids.contains(&notif.id) { all.insert(insert_idx, notif); insert_idx += 1; }
                        }
                        let total_count = all.len() as u32; drop(all);
                        *to.lock().unwrap() = total_count; *ur.lock().unwrap() += new_count;
                        rebuild_list(&lb, &n.borrow(), &ic, &s.borrow());
                        tracing::info!("Poll: {} items ({} new), {} total", nitems, new_count, total_count);
                        if total_count > 0 { ep.set_title("No Notifications"); ep.set_description(Some("")); }
                        else { ep.set_title("No Notifications"); ep.set_description(Some("You're all caught up.")); }
                    }
                    Err(e) => { tracing::warn!("Poll failed: {e}"); }
                }
            }
            glib::ControlFlow::Continue
        });
    }

    {
        let w = window.clone();
        glib::idle_add_local(move || {
            if toggle_rx.try_recv().is_ok() {
                if w.is_visible() { w.set_visible(false); } else { w.present(); }
            }
            glib::ControlFlow::Continue
        });
    }

    window.present(); window.set_visible(false);

    {
        let a = api.clone(); let tx = poll_tx.clone();
        std::thread::spawn(move || { let _ = tx.send(a.notifications(None, PAGE_COUNT).map_err(|e| e.to_string())); });
    }

    let _settings_rc = settings_rc;
    let _window_width = window_width;
    glib::timeout_add_seconds_local(poll_interval as u32, move || {
        let a = api.clone(); let tx = poll_tx.clone();
        std::thread::spawn(move || { let _ = tx.send(a.notifications(None, PAGE_COUNT).map_err(|e| e.to_string())); });
        glib::ControlFlow::Continue
    });
}
